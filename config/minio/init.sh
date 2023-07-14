#!/bin/sh

set -eu

mc config host rm local/ >/dev/null 2>&1 ||:
printenv MINIO_ROOT_PASSWORD | mc config host add --api S3v4 local/ "http://minio:9000" minio

for policy_file in /policies/*.json; do
	policy_name="$(basename "${policy_file:?}" .json)"
	if ! mc admin policy info local/ "${policy_name:?}" >/dev/null 2>&1; then
		mc admin policy create local/ "${policy_name:?}" "${policy_file:?}"
	fi
done

if ! mc admin user info local/ grist >/dev/null 2>&1; then
	printenv MINIO_GRIST_PASSWORD | mc admin user add local/ grist
	mc admin policy attach local/ grist-readwrite --user grist
fi

if ! mc stat local/grist >/dev/null 2>&1; then
	mc mb local/grist
	mc anonymous set private local/grist
	mc version enable local/grist
	mc ilm rule add local/grist \
		--noncurrent-expire-newer 10 \
		--noncurrent-expire-days 180 \
		--expire-delete-marker
fi
