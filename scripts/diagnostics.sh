#!/bin/sh
set -eu

printf '%s\n' 'SavaPage diagnostics (secrets redacted)'
printf 'SavaPage image version: %s\n' "${SAVAPAGE_VERSION:-unknown}"
printf 'Installed version: '
cat /opt/savapage/.image-version 2>/dev/null || printf '%s\n' unknown
java -version 2>&1 | sed -n '1,2p'
printf 'PostgreSQL: '
if PGPASSWORD=${SAVAPAGE_DB_PASSWORD:-} pg_isready --quiet \
    --host "${SAVAPAGE_DB_HOST:-postgres}" --port "${SAVAPAGE_DB_PORT:-5432}" \
    --username "${SAVAPAGE_DB_USER:-savapage}" --dbname "${SAVAPAGE_DB_NAME:-savapage}"; then
    printf '%s\n' ready
else
    printf '%s\n' unavailable
fi
printf 'CUPS: '
cups-config --version 2>/dev/null || printf '%s\n' unknown
lpstat -r 2>&1 || true
printf '%s\n' 'Configured queues:'
lpstat -v 2>&1 || true
printf '%s\n' 'Persistent paths:'
for path in /opt/savapage/server/data /opt/savapage/server/logs /etc/cups /var/lib/cups /var/cache/cups /var/spool/cups; do
    printf '  %s: ' "${path}"
    df -hP "${path}" 2>/dev/null | awk 'NR == 2 {print $4 " free on " $1}' || printf '%s\n' unavailable
done
printf 'CUPS health: '
/usr/local/bin/healthcheck-cups >/dev/null 2>&1 && printf '%s\n' healthy || printf '%s\n' unhealthy
printf 'SavaPage health: '
/usr/local/bin/healthcheck-savapage >/dev/null 2>&1 && printf '%s\n' healthy || printf '%s\n' unhealthy

