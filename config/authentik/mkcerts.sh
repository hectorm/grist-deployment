#!/bin/sh

set -eu
export LC_ALL='C'

# export LD_PRELOAD='/usr/lib/faketime/libfaketime.so.1'
# export FAKETIME='1970-01-01 00:00:00'

{
	set -a

	CERTS_DIR="$(CDPATH='' cd -- "$(dirname -- "${0:?}")" && pwd -P)"/certs/
	BLUEPRINTS_DIR="$(CDPATH='' cd -- "$(dirname -- "${0:?}")" && pwd -P)"/blueprints/

	CA_KEY="${CERTS_DIR:?}"/ca/ca.key
	CA_CSR="${CERTS_DIR:?}"/ca/ca.csr
	CA_SRL="${CERTS_DIR:?}"/ca/ca.srl
	CA_CRT="${CERTS_DIR:?}"/ca/ca.crt
	CA_CRT_CNF="${CERTS_DIR:?}"/ca/ca.cnf
	CA_CRT_BLUEPRINT="${BLUEPRINTS_DIR:?}"/authentik-ca-certificate.yaml
	CA_CRT_SUBJ='/CN=authentik CA'
	CA_CRT_VALIDITY_DAYS='7300'
	CA_CRT_RENOVATION_DAYS='30'
	CA_RENEW_PREHOOK=''
	CA_RENEW_POSTHOOK=''

	JWT_KEY="${CERTS_DIR:?}"/jwt/jwt.key
	JWT_CSR="${CERTS_DIR:?}"/jwt/jwt.csr
	JWT_CRT="${CERTS_DIR:?}"/jwt/jwt.crt
	JWT_CRT_CNF="${CERTS_DIR:?}"/jwt/jwt.cnf
	JWT_CRT_CA="${CERTS_DIR:?}"/jwt/ca.crt
	JWT_CRT_FULLCHAIN="${CERTS_DIR:?}"/jwt/fullchain.crt
	JWT_CRT_BLUEPRINT="${BLUEPRINTS_DIR:?}"/jwt-certificate.yaml
	JWT_CRT_SUBJ='/CN=JWT'
	JWT_CRT_VALIDITY_DAYS='7300'
	JWT_CRT_RENOVATION_DAYS='30'
	JWT_RENEW_PREHOOK=''
	JWT_RENEW_POSTHOOK=''

	set +a
}

if [ ! -e "${CERTS_DIR:?}"/ca/ ]; then mkdir -p "${CERTS_DIR:?}"/ca/; fi
if [ ! -e "${CERTS_DIR:?}"/jwt/ ]; then mkdir -p "${CERTS_DIR:?}"/jwt/; fi

# Generate CA private key if it does not exist
if [ ! -e "${CA_KEY:?}" ] \
	|| ! openssl rsa -check -in "${CA_KEY:?}" -noout >/dev/null 2>&1
then
	printf '%s\n' 'Generating CA private key...'
	openssl genrsa -out "${CA_KEY:?}" 4096
fi

# Generate CA certificate if it does not exist or will expire soon
if [ ! -e "${CA_CRT:?}" ] || [ ! -e "${CA_CRT_BLUEPRINT:?}" ] \
	|| [ "$(openssl x509 -pubkey -in "${CA_CRT:?}" -noout 2>/dev/null)" != "$(openssl pkey -pubout -in "${CA_KEY:?}" -outform PEM 2>/dev/null)" ] \
	|| ! openssl x509 -checkend "$((60*60*24*CA_CRT_RENOVATION_DAYS))" -in "${CA_CRT:?}" -noout >/dev/null 2>&1
then
	if [ -n "${CA_RENEW_PREHOOK?}" ]; then
		sh -euc "${CA_RENEW_PREHOOK:?}"
	fi

	printf '%s\n' 'Generating CA certificate...'
	openssl req -new \
		-key "${CA_KEY:?}" \
		-out "${CA_CSR:?}" \
		-subj "${CA_CRT_SUBJ:?}"
	cat > "${CA_CRT_CNF:?}" <<-EOF
		[ x509_exts ]
		subjectKeyIdentifier = hash
		authorityKeyIdentifier = keyid:always,issuer:always
		basicConstraints = critical,CA:TRUE,pathlen:0
		keyUsage = critical,keyCertSign,cRLSign
	EOF
	openssl x509 -req \
		-in "${CA_CSR:?}" \
		-out "${CA_CRT:?}" \
		-signkey "${CA_KEY:?}" \
		-days "${CA_CRT_VALIDITY_DAYS:?}" \
		-sha256 \
		-extfile "${CA_CRT_CNF:?}" \
		-extensions x509_exts
	openssl x509 -in "${CA_CRT:?}" -fingerprint -noout

	printf '%s\n' 'Generating CA certificate blueprint...'
	cat > "${CA_CRT_BLUEPRINT:?}" <<-EOF
		# yaml-language-server: \$schema=https://version-2023-4.goauthentik.io/blueprints/schema.json
		version: 1
		metadata:
		  name: "authentik CA certificate"
		  labels:
		    blueprints.goauthentik.io/description: "authentik CA certificate"
		    blueprints.goauthentik.io/instantiate: "true"
		entries:
		  # authentik CA certificate
		  - id: "authentik-ca-certificate"
		    identifiers:
		      name: "authentik CA certificate"
		    model: "authentik_crypto.certificatekeypair"
		    attrs:
		      name: "authentik CA certificate"
		      $(awk 'BEGIN { printf("%s\n", "key_data: |-")         } { printf("        %s\n", $0) }' < "${CA_KEY:?}")
		      $(awk 'BEGIN { printf("%s\n", "certificate_data: |-") } { printf("        %s\n", $0) }' < "${CA_CRT:?}")
	EOF

	if [ -n "${CA_RENEW_POSTHOOK?}" ]; then
		sh -euc "${CA_RENEW_POSTHOOK:?}"
	fi
fi

# Generate JWT private key if it does not exist
if [ ! -e "${JWT_KEY:?}" ] \
	|| ! openssl rsa -check -in "${JWT_KEY:?}" -noout >/dev/null 2>&1
then
	printf '%s\n' 'Generating JWT private key...'
	openssl genrsa -out "${JWT_KEY:?}" 4096
fi

# Generate JWT certificate if it does not exist or will expire soon
if [ ! -e "${JWT_CRT:?}" ] || [ ! -e "${JWT_CRT_BLUEPRINT:?}" ] \
	|| [ "$(openssl x509 -pubkey -in "${JWT_CRT:?}" -noout 2>/dev/null)" != "$(openssl pkey -pubout -in "${JWT_KEY:?}" -outform PEM 2>/dev/null)" ] \
	|| ! openssl verify -CAfile "${CA_CRT:?}" "${JWT_CRT:?}" >/dev/null 2>&1 \
	|| ! openssl x509 -checkend "$((60*60*24*JWT_CRT_RENOVATION_DAYS))" -in "${JWT_CRT:?}" -noout >/dev/null 2>&1
then
	if [ -n "${JWT_RENEW_PREHOOK?}" ]; then
		sh -euc "${JWT_RENEW_PREHOOK:?}"
	fi

	printf '%s\n' 'Generating JWT certificate...'
	openssl req -new \
		-key "${JWT_KEY:?}" \
		-out "${JWT_CSR:?}" \
		-subj "${JWT_CRT_SUBJ:?}"
	cat > "${JWT_CRT_CNF:?}" <<-EOF
		[ x509_exts ]
		basicConstraints = critical,CA:FALSE
		keyUsage = critical,digitalSignature
		extendedKeyUsage = critical,serverAuth
	EOF
	openssl x509 -req \
		-in "${JWT_CSR:?}" \
		-out "${JWT_CRT:?}" \
		-CA "${CA_CRT:?}" \
		-CAkey "${CA_KEY:?}" \
		-CAserial "${CA_SRL:?}" -CAcreateserial \
		-days "${JWT_CRT_VALIDITY_DAYS:?}" \
		-sha256 \
		-extfile "${JWT_CRT_CNF:?}" \
		-extensions x509_exts
	openssl x509 -in "${JWT_CRT:?}" -fingerprint -noout

	cat "${CA_CRT:?}" > "${JWT_CRT_CA:?}"
	cat "${JWT_CRT:?}" "${JWT_CRT_CA:?}" > "${JWT_CRT_FULLCHAIN:?}"

	printf '%s\n' 'Generating JWT certificate blueprint...'
	cat > "${JWT_CRT_BLUEPRINT:?}" <<-EOF
		# yaml-language-server: \$schema=https://version-2023-4.goauthentik.io/blueprints/schema.json
		version: 1
		metadata:
		  name: "JWT certificate"
		  labels:
		    blueprints.goauthentik.io/description: "JWT certificate"
		    blueprints.goauthentik.io/instantiate: "true"
		entries:
		  # Apply "authentik CA certificate" blueprint
		  - model: "authentik_blueprints.metaapplyblueprint"
		    attrs:
		      identifiers:
		        name: "authentik CA certificate"
		      required: true
		  # JWT certificate
		  - id: "jwt-certificate"
		    identifiers:
		      name: "JWT certificate"
		    model: "authentik_crypto.certificatekeypair"
		    attrs:
		      name: "JWT certificate"
		      $(awk 'BEGIN { printf("%s\n", "key_data: |-")         } { printf("        %s\n", $0) }' < "${JWT_KEY:?}")
		      $(awk 'BEGIN { printf("%s\n", "certificate_data: |-") } { printf("        %s\n", $0) }' < "${JWT_CRT:?}")
	EOF

	if [ -n "${JWT_RENEW_POSTHOOK?}" ]; then
		sh -euc "${JWT_RENEW_POSTHOOK:?}"
	fi
fi
