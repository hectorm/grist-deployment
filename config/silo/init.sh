#!/bin/sh

set -eu

mc alias rm local >/dev/null 2>&1 ||:
printenv SILO_ROOT_PASSWORD | mc alias set --api S3v4 local "http://silo:9000" silo

for policy_file in /policies/*.json; do
	policy_name="$(basename "${policy_file:?}" .json)"
	if ! mc admin policy info local/ "${policy_name:?}" >/dev/null 2>&1; then
		mc admin policy create local/ "${policy_name:?}" "${policy_file:?}"
	fi
done

if ! mc admin user info local/ grist >/dev/null 2>&1; then
	printenv SILO_GRIST_PASSWORD | mc admin user add local/ grist
	mc admin policy attach local/ grist-readwrite --user grist
fi

if ! mc stat local/grist >/dev/null 2>&1; then
	mc mb local/grist
	mc anonymous set private local/grist
	mc version enable local/grist
fi

mc ilm rule rm --all --force local/grist >/dev/null 2>&1 ||:
mc ilm rule add local/grist \
	--prefix "docs/assets/unversioned/" \
	--noncurrent-expire-days 1
