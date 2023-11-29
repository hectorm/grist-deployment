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

	SAML_IDP_KEY="${CERTS_DIR:?}"/saml-idp/saml-idp.key
	SAML_IDP_CSR="${CERTS_DIR:?}"/saml-idp/saml-idp.csr
	SAML_IDP_CRT="${CERTS_DIR:?}"/saml-idp/saml-idp.crt
	SAML_IDP_CRT_CNF="${CERTS_DIR:?}"/saml-idp/saml-idp.cnf
	SAML_IDP_CRT_CA="${CERTS_DIR:?}"/saml-idp/ca.crt
	SAML_IDP_CRT_FULLCHAIN="${CERTS_DIR:?}"/saml-idp/fullchain.crt
	SAML_IDP_CRT_BLUEPRINT="${BLUEPRINTS_DIR:?}"/saml-idp-certificate.yaml
	SAML_IDP_CRT_SUBJ='/CN=SAML IdP'
	SAML_IDP_CRT_VALIDITY_DAYS='7300'
	SAML_IDP_CRT_RENOVATION_DAYS='30'
	SAML_IDP_RENEW_PREHOOK=''
	SAML_IDP_RENEW_POSTHOOK=''

	SAML_GRIST_SP_KEY="${CERTS_DIR:?}"/saml-grist-sp/saml-grist-sp.key
	SAML_GRIST_SP_CSR="${CERTS_DIR:?}"/saml-grist-sp/saml-grist-sp.csr
	SAML_GRIST_SP_CRT="${CERTS_DIR:?}"/saml-grist-sp/saml-grist-sp.crt
	SAML_GRIST_SP_CRT_CNF="${CERTS_DIR:?}"/saml-grist-sp/saml-grist-sp.cnf
	SAML_GRIST_SP_CRT_CA="${CERTS_DIR:?}"/saml-grist-sp/ca.crt
	SAML_GRIST_SP_CRT_FULLCHAIN="${CERTS_DIR:?}"/saml-grist-sp/fullchain.crt
	SAML_GRIST_SP_CRT_BLUEPRINT="${BLUEPRINTS_DIR:?}"/saml-grist-sp-certificate.yaml
	SAML_GRIST_SP_CRT_SUBJ='/CN=SAML Grist SP'
	SAML_GRIST_SP_CRT_VALIDITY_DAYS='7300'
	SAML_GRIST_SP_CRT_RENOVATION_DAYS='30'
	SAML_GRIST_SP_IDP_CRT="${CERTS_DIR:?}"/saml-grist-sp/saml-idp.crt
	SAML_GRIST_SP_RENEW_PREHOOK=''
	SAML_GRIST_SP_RENEW_POSTHOOK=''

	set +a
}

if [ ! -e "${CERTS_DIR:?}"/ca/ ]; then mkdir -p "${CERTS_DIR:?}"/ca/; fi
if [ ! -e "${CERTS_DIR:?}"/saml-idp/ ]; then mkdir -p "${CERTS_DIR:?}"/saml-idp/; fi
if [ ! -e "${CERTS_DIR:?}"/saml-grist-sp/ ]; then mkdir -p "${CERTS_DIR:?}"/saml-grist-sp/; fi

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

# Generate SAML IdP private key if it does not exist
if [ ! -e "${SAML_IDP_KEY:?}" ] \
	|| ! openssl rsa -check -in "${SAML_IDP_KEY:?}" -noout >/dev/null 2>&1
then
	printf '%s\n' 'Generating SAML IdP private key...'
	openssl genrsa -out "${SAML_IDP_KEY:?}" 4096
fi

# Generate SAML IdP certificate if it does not exist or will expire soon
if [ ! -e "${SAML_IDP_CRT:?}" ] || [ ! -e "${SAML_IDP_CRT_BLUEPRINT:?}" ] \
	|| [ "$(openssl x509 -pubkey -in "${SAML_IDP_CRT:?}" -noout 2>/dev/null)" != "$(openssl pkey -pubout -in "${SAML_IDP_KEY:?}" -outform PEM 2>/dev/null)" ] \
	|| ! openssl verify -CAfile "${CA_CRT:?}" "${SAML_IDP_CRT:?}" >/dev/null 2>&1 \
	|| ! openssl x509 -checkend "$((60*60*24*SAML_IDP_CRT_RENOVATION_DAYS))" -in "${SAML_IDP_CRT:?}" -noout >/dev/null 2>&1
then
	if [ -n "${SAML_IDP_RENEW_PREHOOK?}" ]; then
		sh -euc "${SAML_IDP_RENEW_PREHOOK:?}"
	fi

	printf '%s\n' 'Generating SAML IdP certificate...'
	openssl req -new \
		-key "${SAML_IDP_KEY:?}" \
		-out "${SAML_IDP_CSR:?}" \
		-subj "${SAML_IDP_CRT_SUBJ:?}"
	cat > "${SAML_IDP_CRT_CNF:?}" <<-EOF
		[ x509_exts ]
		basicConstraints = critical,CA:FALSE
		keyUsage = critical,digitalSignature
		extendedKeyUsage = critical,serverAuth
	EOF
	openssl x509 -req \
		-in "${SAML_IDP_CSR:?}" \
		-out "${SAML_IDP_CRT:?}" \
		-CA "${CA_CRT:?}" \
		-CAkey "${CA_KEY:?}" \
		-CAserial "${CA_SRL:?}" -CAcreateserial \
		-days "${SAML_IDP_CRT_VALIDITY_DAYS:?}" \
		-sha256 \
		-extfile "${SAML_IDP_CRT_CNF:?}" \
		-extensions x509_exts
	openssl x509 -in "${SAML_IDP_CRT:?}" -fingerprint -noout

	cat "${CA_CRT:?}" > "${SAML_IDP_CRT_CA:?}"
	cat "${SAML_IDP_CRT:?}" "${SAML_IDP_CRT_CA:?}" > "${SAML_IDP_CRT_FULLCHAIN:?}"

	printf '%s\n' 'Generating SAML IdP certificate blueprint...'
	cat > "${SAML_IDP_CRT_BLUEPRINT:?}" <<-EOF
		# yaml-language-server: \$schema=https://version-2023-4.goauthentik.io/blueprints/schema.json
		version: 1
		metadata:
		  name: "SAML IdP certificate"
		  labels:
		    blueprints.goauthentik.io/description: "SAML IdP certificate"
		    blueprints.goauthentik.io/instantiate: "true"
		entries:
		  # Apply "authentik CA certificate" blueprint
		  - model: "authentik_blueprints.metaapplyblueprint"
		    attrs:
		      identifiers:
		        name: "authentik CA certificate"
		      required: true
		  # SAML IdP certificate
		  - id: "saml-idp-certificate"
		    identifiers:
		      name: "SAML IdP certificate"
		    model: "authentik_crypto.certificatekeypair"
		    attrs:
		      name: "SAML IdP certificate"
		      $(awk 'BEGIN { printf("%s\n", "key_data: |-")         } { printf("        %s\n", $0) }' < "${SAML_IDP_KEY:?}")
		      $(awk 'BEGIN { printf("%s\n", "certificate_data: |-") } { printf("        %s\n", $0) }' < "${SAML_IDP_CRT:?}")
	EOF

	if [ -n "${SAML_IDP_RENEW_POSTHOOK?}" ]; then
		sh -euc "${SAML_IDP_RENEW_POSTHOOK:?}"
	fi
fi

# Generate SAML Grist SP private key if it does not exist
if [ ! -e "${SAML_GRIST_SP_KEY:?}" ] \
	|| ! openssl rsa -check -in "${SAML_GRIST_SP_KEY:?}" -noout >/dev/null 2>&1
then
	printf '%s\n' 'Generating SAML Grist SP private key...'
	openssl genrsa -out "${SAML_GRIST_SP_KEY:?}" 4096
fi

# Generate SAML Grist SP certificate if it does not exist or will expire soon
if [ ! -e "${SAML_GRIST_SP_CRT:?}" ] || [ ! -e "${SAML_GRIST_SP_CRT_BLUEPRINT:?}" ] \
	|| [ "$(openssl x509 -pubkey -in "${SAML_GRIST_SP_CRT:?}" -noout 2>/dev/null)" != "$(openssl pkey -pubout -in "${SAML_GRIST_SP_KEY:?}" -outform PEM 2>/dev/null)" ] \
	|| ! openssl verify -CAfile "${CA_CRT:?}" "${SAML_GRIST_SP_CRT:?}" >/dev/null 2>&1 \
	|| ! openssl x509 -checkend "$((60*60*24*SAML_GRIST_SP_CRT_RENOVATION_DAYS))" -in "${SAML_GRIST_SP_CRT:?}" -noout >/dev/null 2>&1
then
	if [ -n "${SAML_GRIST_SP_RENEW_PREHOOK?}" ]; then
		sh -euc "${SAML_GRIST_SP_RENEW_PREHOOK:?}"
	fi

	printf '%s\n' 'Generating SAML Grist SP certificate...'
	openssl req -new \
		-key "${SAML_GRIST_SP_KEY:?}" \
		-out "${SAML_GRIST_SP_CSR:?}" \
		-subj "${SAML_GRIST_SP_CRT_SUBJ:?}"
	cat > "${SAML_GRIST_SP_CRT_CNF:?}" <<-EOF
		[ x509_exts ]
		basicConstraints = critical,CA:FALSE
		keyUsage = critical,digitalSignature
		extendedKeyUsage = critical,serverAuth
	EOF
	openssl x509 -req \
		-in "${SAML_GRIST_SP_CSR:?}" \
		-out "${SAML_GRIST_SP_CRT:?}" \
		-CA "${CA_CRT:?}" \
		-CAkey "${CA_KEY:?}" \
		-CAserial "${CA_SRL:?}" -CAcreateserial \
		-days "${SAML_GRIST_SP_CRT_VALIDITY_DAYS:?}" \
		-sha256 \
		-extfile "${SAML_GRIST_SP_CRT_CNF:?}" \
		-extensions x509_exts
	openssl x509 -in "${SAML_GRIST_SP_CRT:?}" -fingerprint -noout

	cat "${CA_CRT:?}" > "${SAML_GRIST_SP_CRT_CA:?}"
	cat "${SAML_IDP_CRT:?}" > "${SAML_GRIST_SP_IDP_CRT:?}"
	cat "${SAML_GRIST_SP_CRT:?}" "${SAML_GRIST_SP_CRT_CA:?}" > "${SAML_GRIST_SP_CRT_FULLCHAIN:?}"

	printf '%s\n' 'Generating SAML Grist SP certificate blueprint...'
	cat > "${SAML_GRIST_SP_CRT_BLUEPRINT:?}" <<-EOF
		# yaml-language-server: \$schema=https://version-2023-4.goauthentik.io/blueprints/schema.json
		version: 1
		metadata:
		  name: "SAML Grist SP certificate"
		  labels:
		    blueprints.goauthentik.io/description: "SAML Grist SP certificate"
		    blueprints.goauthentik.io/instantiate: "true"
		entries:
		  # Apply "authentik CA certificate" blueprint
		  - model: "authentik_blueprints.metaapplyblueprint"
		    attrs:
		      identifiers:
		        name: "authentik CA certificate"
		      required: true
		  # SAML Grist SP certificate
		  - id: "saml-grist-sp-certificate"
		    identifiers:
		      name: "SAML Grist SP certificate"
		    model: "authentik_crypto.certificatekeypair"
		    attrs:
		      name: "SAML Grist SP certificate"
		      $(awk 'BEGIN { printf("%s\n", "certificate_data: |-") } { printf("        %s\n", $0) }' < "${SAML_GRIST_SP_CRT:?}")
	EOF

	if [ -n "${SAML_GRIST_SP_RENEW_POSTHOOK?}" ]; then
		sh -euc "${SAML_GRIST_SP_RENEW_POSTHOOK:?}"
	fi
fi
