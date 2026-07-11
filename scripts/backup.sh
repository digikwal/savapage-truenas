#!/bin/sh
set -eu

backup_root=${1:-./backups}
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_dir=${backup_root%/}/savapage-${timestamp}
compose=${COMPOSE_FILE:-compose.yaml}

umask 077
mkdir -p "${backup_dir}"

docker compose -f "${compose}" exec -T postgres \
    pg_dump --format=custom --no-owner --no-acl \
    --username "${POSTGRES_USER:-savapage}" "${POSTGRES_DB:-savapage}" \
    > "${backup_dir}/postgres.dump"

docker compose -f "${compose}" exec -T savapage \
    tar --create --gzip --directory / \
    opt/savapage/server/data opt/savapage/server/logs \
    etc/cups var/lib/cups var/cache/cups var/spool/cups \
    > "${backup_dir}/files.tar.gz"

docker compose -f "${compose}" images --format json > "${backup_dir}/images.json"
docker compose -f "${compose}" config > "${backup_dir}/compose.rendered.yaml"
sed -i -E \
    -e 's/(POSTGRES_PASSWORD:).*/\1 REDACTED/' \
    -e 's/(SAVAPAGE_DB_PASSWORD:).*/\1 REDACTED/' \
    -e 's/(CUPS_ADMIN_PASSWORD:).*/\1 REDACTED/' \
    "${backup_dir}/compose.rendered.yaml"

test -s "${backup_dir}/postgres.dump"
test -s "${backup_dir}/files.tar.gz"
tar -tzf "${backup_dir}/files.tar.gz" > "${backup_dir}/files.manifest"
grep -q 'opt/savapage/server/data/encryption.properties' "${backup_dir}/files.manifest" || {
    echo 'Backup is incomplete: encryption.properties is missing' >&2
    exit 1
}

(
    cd "${backup_dir}"
    sha256sum postgres.dump files.tar.gz files.manifest images.json compose.rendered.yaml > SHA256SUMS
)

printf 'Application-consistent backup created: %s\n' "${backup_dir}"
