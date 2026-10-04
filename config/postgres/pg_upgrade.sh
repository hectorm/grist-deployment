#!/bin/sh

set -eu
export LC_ALL=C

DOCKER=$(command -v docker 2>/dev/null)

PGVER_OLD=${1:?}
PGVER_NEW=${2:?}
DATA_VOLUME=${3:?}

: "PGUSER=${PGUSER:="postgres"}"
: "PGDATAOLD=${PGDATAOLD:="/var/lib/postgresql/${PGVER_OLD:?}/docker/"}"
: "PGDATANEW=${PGDATANEW:="/var/lib/postgresql/${PGVER_NEW:?}/docker/"}"
: "POSTGRES_INITDB_ARGS=${POSTGRES_INITDB_ARGS:="--username=${PGUSER:?}"}"

# Detect old layout (pre-18) and move data directory if needed
"${DOCKER:?}" run --rm \
	--env PGUSER="${PGUSER:?}" \
	--env PGDATA="${PGDATAOLD:?}" \
	--env PGVER="${PGVER_OLD:?}" \
	--mount type=volume,src="${DATA_VOLUME:?}",dst=/var/lib/postgresql/ \
	--entrypoint /bin/sh docker.io/alpine:latest \
	-euc "$(cat <<-'EOF'
		if [ -f /var/lib/postgresql/PG_VERSION ]; then
			printf "Moving old data directory to new layout...\n"
			cd /var/lib/postgresql/
			mkdir -p ./"${PGVER:?}"/docker/
			find . '!' -name . -prune '!' -name "${PGVER:?}" -exec sh -c 'mv "$@" "${PGVER:?}"/docker' -- '{}' '+'
		fi
	EOF
	)"

# Determine if data checksums are enabled
CHECKSUM_STATUS=$("${DOCKER:?}" run --rm \
	--env PGUSER="${PGUSER:?}" \
	--env PGDATA="${PGDATAOLD:?}" \
	--mount type=volume,src="${DATA_VOLUME:?}",dst=/var/lib/postgresql/ \
	--entrypoint /usr/lib/postgresql/"${PGVER_OLD}"/bin/pg_controldata docker.io/postgres:"${PGVER_OLD:?}" \
	"${PGDATAOLD:?}" | awk '/Data page checksum version/{print($NF)}')
if [ "${CHECKSUM_STATUS:?}" = "1" ]; then
	POSTGRES_UPGRADE_INITDB_ARGS="${POSTGRES_INITDB_ARGS:?} --data-checksums"
else
	POSTGRES_UPGRADE_INITDB_ARGS="${POSTGRES_INITDB_ARGS:?} --no-data-checksums"
fi

# Perform the upgrade
"${DOCKER:?}" run --rm \
	--env PGUSER="${PGUSER:?}" \
	--env PGDATAOLD="${PGDATAOLD:?}" \
	--env PGDATANEW="${PGDATANEW:?}" \
	--env POSTGRES_INITDB_ARGS="${POSTGRES_UPGRADE_INITDB_ARGS:?}" \
	--mount type=volume,src="${DATA_VOLUME:?}",dst=/var/lib/postgresql/ \
	docker.io/tianon/postgres-upgrade:"${PGVER_OLD:?}"-to-"${PGVER_NEW:?}" --link

# Post-upgrade procedure
"${DOCKER:?}" run --rm \
	--env PGUSER="${PGUSER:?}" \
	--env PGDATA="${PGDATANEW:?}" \
	--env PGDATAOLD="${PGDATAOLD:?}" \
	--env PGDATANEW="${PGDATANEW:?}" \
	--env POSTGRES_INITDB_ARGS="${POSTGRES_INITDB_ARGS:?}" \
	--mount type=volume,src="${DATA_VOLUME:?}",dst=/var/lib/postgresql/ \
	--entrypoint /bin/sh docker.io/postgres:"${PGVER_NEW:?}" \
	-euc "$(cat <<-'EOF'
		set -eux

		# Restore host auth method
		if ! grep -q '^host all all all' "${PGDATANEW:?}"/pg_hba.conf; then
			awk '/^host all all all/{printf("\n%s\n",$0)}' "${PGDATAOLD:?}"/pg_hba.conf >> "${PGDATANEW:?}"/pg_hba.conf
		fi

		# Enable checksums if missing
		if [ "$(pg_controldata "${PGDATANEW:?}" | awk '/Data page checksum version/{print($NF)}')" != "1" ]; then
			pg_checksums --enable --progress
		fi

		# Start Postgres
		gosu postgres postgres & until pg_isready; do sleep 1; done

		# Reindex (required for glibc changes) and refresh collation
		reindexdb --all && psql -c "DO \$\$ DECLARE db record; BEGIN
			FOR db IN SELECT datname FROM pg_database WHERE datname != 'template0' AND datallowconn
			LOOP EXECUTE FORMAT('ALTER DATABASE %I REFRESH COLLATION VERSION;', db.datname);
			END LOOP;
		END; \$\$;"

		# Generate missing query optimizer statistics
		vacuumdb --all --analyze-in-stages --missing-stats-only

		# Stop Postgres
		gosu postgres pg_ctl stop -m fast -w

		# Delete old cluster data
		rm -rf "${PGDATAOLD:?}"
	EOF
	)"
