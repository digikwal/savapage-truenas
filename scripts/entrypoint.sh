#!/bin/bash
set -eu
set -o pipefail

readonly SP_HOME=/opt/savapage
readonly SP_SERVER_HOME=${SP_HOME}/server
readonly SP_DATA=${SP_SERVER_HOME}/data
readonly SP_LOGS=${SP_SERVER_HOME}/logs
readonly SP_PID=${SP_LOGS}/service.pid

log() {
    printf '[savapage-entrypoint] %s\n' "$*"
}

fatal() {
    printf '[savapage-entrypoint] ERROR: %s\n' "$*" >&2
    exit 1
}

require() {
    local name=$1
    test -n "${!name:-}" || fatal "Required environment variable ${name} is empty"
}

is_true() {
    case "${1:-false}" in
        true|TRUE|1|yes|YES) return 0 ;;
        false|FALSE|0|no|NO|'') return 1 ;;
        *) fatal "Invalid boolean value: ${1}" ;;
    esac
}

validate_port() {
    local name=$1 value=${!1:-}
    case "${value}" in
        ''|*[!0-9]*) fatal "${name} must be a numeric port" ;;
    esac
    (( value >= 1024 && value <= 65535 )) || fatal "${name} must be between 1024 and 65535"
}

validate_integer() {
    local name=$1 value=${!1:-} minimum=$2
    case "${value}" in
        ''|*[!0-9]*) fatal "${name} must be an integer" ;;
    esac
    (( value >= minimum )) || fatal "${name} must be at least ${minimum}"
}

validate_config() {
    require SAVAPAGE_DB_HOST
    require SAVAPAGE_DB_PORT
    require SAVAPAGE_DB_NAME
    require SAVAPAGE_DB_USER
    require SAVAPAGE_DB_PASSWORD

    validate_port SAVAPAGE_HTTP_PORT
    validate_port SAVAPAGE_HTTPS_PORT
    validate_port SAVAPAGE_LOCAL_HTTPS_PORT
    validate_port SAVAPAGE_RAW_PORT
    validate_integer SAVAPAGE_DB_POOL_MAX 5
    validate_integer CUPS_MAX_JOBS 500

    if is_true "${ENABLE_X_FORWARDED_FOR:-false}" && test -z "${ALLOWED_PROXY_CIDRS:-}"; then
        fatal "ALLOWED_PROXY_CIDRS is required when X-Forwarded-For processing is enabled"
    fi
    if is_true "${ENABLE_AIRPRINT:-false}" && ! is_true "${HOST_NETWORK:-false}"; then
        fatal "AirPrint requires explicit host networking"
    fi
    if is_true "${ENABLE_AIRPRINT:-false}" \
        && ! is_true "${AVAHI_ENABLE_IPV4:-true}" \
        && ! is_true "${AVAHI_ENABLE_IPV6:-true}"; then
        fatal "AirPrint requires IPv4, IPv6, or both"
    fi
    if is_true "${ENABLE_CUPS_ADMIN:-false}"; then
        require CUPS_ADMIN_PASSWORD
        test -n "${TRUSTED_LAN_CIDRS:-}" || fatal "TRUSTED_LAN_CIDRS is required for remote CUPS administration"
    fi
    if is_true "${ENABLE_PAM_AUTHENTICATION:-false}" && is_true "${NO_NEW_PRIVILEGES:-true}"; then
        fatal "PAM authentication requires no-new-privileges to be disabled"
    fi

    if test "${SAVAPAGE_HTTP_PORT}" = "${SAVAPAGE_HTTPS_PORT}" \
        || test "${SAVAPAGE_HTTP_PORT}" = "${SAVAPAGE_LOCAL_HTTPS_PORT}" \
        || test "${SAVAPAGE_HTTPS_PORT}" = "${SAVAPAGE_LOCAL_HTTPS_PORT}"; then
        fatal "SavaPage HTTP and HTTPS ports must be unique"
    fi
}

initialize_storage() {
    install -d -o savapage -g savapage -m 0700 "${SP_DATA}" "${SP_LOGS}" "${SP_SERVER_HOME}/tmp"
    install -d -o root -g lp -m 0755 /var/lib/cups /var/cache/cups
    install -d -o root -g lp -m 0710 /var/spool/cups

    if test ! -e "${SP_DATA}/.container-initialized"; then
        log "Initializing persistent SavaPage data without replacing existing files"
        cp -an /usr/share/savapage/default-data/. "${SP_DATA}/"
        chown -R savapage:savapage "${SP_DATA}"
        chmod 0700 "${SP_DATA}"
        : > "${SP_DATA}/.container-initialized"
        chown savapage:savapage "${SP_DATA}/.container-initialized"
    fi

    if test ! -e /etc/cups/cups-files.conf; then
        log "Initializing persistent CUPS configuration"
        cp -an /usr/share/savapage/default-cups/. /etc/cups/
    fi
}

configure_pam() {
    if is_true "${ENABLE_PAM_AUTHENTICATION:-false}"; then
        log "Enabling explicitly requested setuid PAM helper"
        chown root:root "${SP_SERVER_HOME}/bin/linux-x64/savapage-pam"
        chmod 4511 "${SP_SERVER_HOME}/bin/linux-x64/savapage-pam"
    else
        test ! -u "${SP_SERVER_HOME}/bin/linux-x64/savapage-pam" \
            || fatal "PAM helper is unexpectedly setuid while PAM authentication is disabled"
    fi
}

prepare_upgrade() {
    local previous target backup_dir backup_file
    target=$(cat "${SP_HOME}/.image-version")
    previous=$(cat "${SP_DATA}/.container-image-version" 2>/dev/null || true)
    test -n "${previous}" || return 0
    test "${previous}" != "${target}" || return 0

    dpkg --compare-versions "${target}" ge "${previous}" \
        || fatal "Refusing automatic downgrade from ${previous} to ${target}; restore a matching pre-upgrade backup"
    backup_dir=${SP_DATA}/backups
    backup_file=${backup_dir}/pre-upgrade-${previous}-to-${target}-$(date -u +%Y%m%dT%H%M%SZ).tar.gz
    install -d -o savapage -g savapage -m 0700 "${backup_dir}"
    log "Creating pre-upgrade critical-configuration backup"
    tar --create --gzip --file "${backup_file}" --directory "${SP_DATA}" \
        --ignore-failed-read \
        encryption.properties server.properties admin.properties default-ssl-keystore default-ssl-keystore.pw conf
    chown savapage:savapage "${backup_file}"
    UPGRADE_TARGET=${target}
}

complete_upgrade_marker() {
    local target=${UPGRADE_TARGET:-$(cat "${SP_HOME}/.image-version")}
    printf '%s\n' "${target}" > "${SP_DATA}/.container-image-version"
    chown savapage:savapage "${SP_DATA}/.container-image-version"
}

print_cidr_allow_rules() {
    local cidr
    printf '  Allow localhost\n'
    for cidr in ${TRUSTED_LAN_CIDRS//,/ }; do
        test -n "${cidr}" && printf '  Allow from %s\n' "${cidr}"
    done
}

configure_cups() {
    local listen='Listen localhost:631' web='No'
    if is_true "${ENABLE_CUPS_ADMIN:-false}"; then
        listen='Port 631'
        web='Yes'
        printf 'savapage:%s\n' "${CUPS_ADMIN_PASSWORD}" | chpasswd
    fi

    {
        printf '%s\n' "${listen}"
        printf '%s\n' \
            'ServerAlias *' \
            'Browsing Off' \
            'BrowseLocalProtocols none' \
            'DefaultAuthType Basic' \
            "WebInterface ${web}" \
            "MaxJobs ${CUPS_MAX_JOBS}" \
            'PreserveJobHistory Yes' \
            "PreserveJobFiles ${CUPS_PRESERVE_JOB_FILES:-No}" \
            'LogLevel warn' \
            'AccessLogLevel actions' \
            '<Location />'
        if is_true "${ENABLE_CUPS_ADMIN:-false}"; then print_cidr_allow_rules; else printf '  Allow localhost\n'; fi
        printf '%s\n' '</Location>' '<Location /admin>'
        if is_true "${ENABLE_CUPS_ADMIN:-false}"; then print_cidr_allow_rules; else printf '  Allow localhost\n'; fi
        printf '%s\n' \
            '  AuthType Default' \
            '  Require user @SYSTEM' \
            '</Location>' \
            '<Location /admin/conf>' \
            '  AuthType Default' \
            '  Require user @SYSTEM'
        if is_true "${ENABLE_CUPS_ADMIN:-false}"; then print_cidr_allow_rules; else printf '  Allow localhost\n'; fi
        printf '%s\n' \
            '</Location>' \
            '<Policy default>' \
            '  JobPrivateAccess default' \
            '  JobPrivateValues default' \
            '  <Limit Create-Job Print-Job Print-URI Validate-Job Send-Document Send-URI>' \
            '    Order deny,allow' \
            '    Allow localhost' \
            '  </Limit>' \
            '  <Limit CUPS-Get-Document>' \
            '    AuthType Default' \
            '    Require user @OWNER @SYSTEM' \
            '  </Limit>' \
            '  <Limit All>' \
            '    Order deny,allow' \
            '    Allow localhost' \
            '  </Limit>' \
            '</Policy>' \
            '<Policy authenticated>' \
            '  <Limit All>' \
            '    AuthType Default' \
            '    Require user @OWNER @SYSTEM' \
            '  </Limit>' \
            '</Policy>'
    } > /etc/cups/cupsd.conf

    printf '%s\n' 'BrowseRemoteProtocols none' > /etc/cups/cups-browsed.conf
    if is_true "${ENABLE_TEST_FILE_PRINTER:-false}"; then
        if grep -q '^FileDevice ' /etc/cups/cups-files.conf; then
            sed -i 's/^FileDevice .*/FileDevice Yes/' /etc/cups/cups-files.conf
        else
            printf '%s\n' 'FileDevice Yes' >> /etc/cups/cups-files.conf
        fi
    fi
    chmod 0600 /etc/cups/cupsd.conf
}

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

configure_avahi() {
    is_true "${ENABLE_AIRPRINT:-false}" || return 0
    require AIRPRINT_SERVICE_NAME
    require AIRPRINT_HOSTNAME

    install -d -m 0755 /etc/avahi/services
    {
        printf '%s\n' '<?xml version="1.0" standalone="no"?><!DOCTYPE service-group SYSTEM "avahi-service.dtd">' '<service-group>'
        printf '  <name replace-wildcards="yes">%s</name>\n' "$(xml_escape "${AIRPRINT_SERVICE_NAME}")"
        printf '%s\n' '  <service>' '    <type>_ipps._tcp</type>' '    <subtype>_universal._sub._ipps._tcp</subtype>'
        printf '    <port>%s</port>\n' "${SAVAPAGE_HTTPS_PORT}"
        printf '%s\n' '    <txt-record>rp=printers/airprint</txt-record>' '    <txt-record>ty=SavaPage Virtual Printer</txt-record>' '    <txt-record>pdl=application/pdf,application/postscript,image/urf,image/jpeg,image/pwg-raster</txt-record>' '    <txt-record>URF=none</txt-record>' '    <txt-record>Color=T</txt-record>' '    <txt-record>Duplex=F</txt-record>' '  </service>' '  <service>' '    <type>_ipp._tcp</type>' '    <subtype>_universal._sub._ipp._tcp</subtype>'
        printf '    <port>%s</port>\n' "${SAVAPAGE_HTTP_PORT}"
        printf '%s\n' '    <txt-record>rp=printers/airprint</txt-record>' '    <txt-record>ty=SavaPage Virtual Printer</txt-record>' '    <txt-record>pdl=application/pdf,application/postscript,image/urf,image/jpeg,image/pwg-raster</txt-record>' '    <txt-record>URF=none</txt-record>' '  </service>' '</service-group>'
    } > /etc/avahi/services/savapage.service

    sed -i \
        -e "s/^#\?host-name=.*/host-name=${AIRPRINT_HOSTNAME%%.*}/" \
        -e "s/^use-ipv4=.*/use-ipv4=${AVAHI_ENABLE_IPV4:-yes}/" \
        -e "s/^use-ipv6=.*/use-ipv6=${AVAHI_ENABLE_IPV6:-yes}/" \
        /etc/avahi/avahi-daemon.conf
}

set_sp_property() {
    local key=$1 value=$2 index
    index=$(printf '%02d' "${SP_PROPERTY_INDEX}")
    export "SP_SRV_${index}=${key}:${value}"
    SP_PROPERTY_INDEX=$((SP_PROPERTY_INDEX + 1))
}

configure_savapage_environment() {
    SP_PROPERTY_INDEX=1
    export SAVAPAGE_NS=SP_ SP_CONTAINER=DOCKER
    if test -n "${SAVAPAGE_SERVER_HOST:-}"; then
        set_sp_property server.host "${SAVAPAGE_SERVER_HOST}"
    fi
    if is_true "${ENABLE_HTTP:-true}"; then set_sp_property server.port "${SAVAPAGE_HTTP_PORT}"; else set_sp_property server.port 0; fi
    set_sp_property server.ssl.port "${SAVAPAGE_HTTPS_PORT}"
    set_sp_property server.ssl.port.local "${SAVAPAGE_LOCAL_HTTPS_PORT}"
    if is_true "${ENABLE_RAW_PRINT:-false}"; then set_sp_property server.print.port.raw "${SAVAPAGE_RAW_PORT}"; else set_sp_property server.print.port.raw 0; fi
    set_sp_property server.html.redirect.ssl "${REDIRECT_HTTP_TO_HTTPS:-false}"
    set_sp_property database.type PostgreSQL
    set_sp_property database.driver org.postgresql.Driver
    set_sp_property database.url "jdbc:postgresql://${SAVAPAGE_DB_HOST}:${SAVAPAGE_DB_PORT}/${SAVAPAGE_DB_NAME}"
    set_sp_property database.user "${SAVAPAGE_DB_USER}"
    set_sp_property database.password "${SAVAPAGE_DB_PASSWORD}"
    set_sp_property database.connection.pool.max "${SAVAPAGE_DB_POOL_MAX}"
    if is_true "${ENABLE_X_FORWARDED_FOR:-false}"; then
        set_sp_property webserver.http.header.xff.enable Y
        set_sp_property webserver.http.header.xff.proxies.allowed "${ALLOWED_PROXY_CIDRS}"
    fi

    local line key value
    while IFS= read -r line; do
        test -n "${line}" || continue
        key=${line%%=*}
        value=${line#*=}
        test "${key}" != "${line}" || fatal "Additional property must use key=value: ${key}"
        [[ "${key}" =~ ^[A-Za-z0-9_.-]+$ ]] || fatal "Invalid additional property key: ${key}"
        case "${key}" in
            database.*|server.host|server.port|server.ssl.port|server.ssl.port.local|server.print.port.raw|webserver.http.header.xff.*)
                fatal "Additional property overrides a managed key: ${key}" ;;
        esac
        set_sp_property "${key}" "${value}"
    done <<< "${SAVAPAGE_ADDITIONAL_PROPERTIES:-}"
}

wait_for_postgres() {
    local attempt=0
    log "Waiting for PostgreSQL readiness"
    while ! PGPASSWORD="${SAVAPAGE_DB_PASSWORD}" pg_isready --quiet --host "${SAVAPAGE_DB_HOST}" --port "${SAVAPAGE_DB_PORT}" --username "${SAVAPAGE_DB_USER}" --dbname "${SAVAPAGE_DB_NAME}"; do
        attempt=$((attempt + 1))
        (( attempt < 120 )) || fatal "PostgreSQL was not ready after 120 seconds"
        sleep 1
    done
}

initialize_postgres_schema() {
    local psql_base table_count config_table
    psql_base=(psql --no-password --tuples-only --no-align --set ON_ERROR_STOP=1
        --host "${SAVAPAGE_DB_HOST}" --port "${SAVAPAGE_DB_PORT}"
        --username "${SAVAPAGE_DB_USER}" --dbname "${SAVAPAGE_DB_NAME}")
    export PGPASSWORD=${SAVAPAGE_DB_PASSWORD}
    config_table=$("${psql_base[@]}" --command "SELECT to_regclass('public.tbl_config') IS NOT NULL" | tr -d '[:space:]')
    test "${config_table}" != t || return 0

    table_count=$("${psql_base[@]}" --command "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'" | tr -d '[:space:]')
    test "${table_count}" = 0 \
        || fatal "PostgreSQL contains a partial or foreign schema but tbl_config is missing; restore or clean the database"
    log "Initializing empty PostgreSQL database with SavaPage's official db-init tool"
    runuser --user savapage -- sh -c \
        "cd '${SP_SERVER_HOME}/bin/linux-x64' && ./savapage-db --db-init" >/dev/null
    config_table=$("${psql_base[@]}" --command "SELECT to_regclass('public.tbl_config') IS NOT NULL" | tr -d '[:space:]')
    test "${config_table}" = t || fatal "SavaPage db-init did not create tbl_config"
}

# shellcheck disable=SC2317 # Invoked by the signal/EXIT trap.
shutdown() {
    log "Stopping services"
    runuser --user savapage -- "${SP_SERVER_HOME}/bin/linux-x64/app-server" stop >/dev/null 2>&1 || true
    test -z "${CUPSD_PID:-}" || kill "${CUPSD_PID}" 2>/dev/null || true
    test -z "${AVAHI_PID:-}" || kill "${AVAHI_PID}" 2>/dev/null || true
}

main() {
    validate_config
    initialize_storage
    configure_pam
    configure_cups
    configure_avahi
    configure_savapage_environment
    prepare_upgrade
    wait_for_postgres
    initialize_postgres_schema

    trap shutdown TERM INT EXIT
    log "Starting CUPS without deleting queues, spool, cache, or job-ID state"
    /usr/sbin/cupsd -f &
    CUPSD_PID=$!
    sleep 2
    /usr/local/bin/healthcheck-cups

    if is_true "${ENABLE_AIRPRINT:-false}"; then
        mkdir -p /run/dbus
        dbus-daemon --system --fork
        avahi-daemon --no-chroot --debug &
        AVAHI_PID=$!
    fi

    log "Starting SavaPage ${SAVAPAGE_VERSION} as user savapage"
    runuser --user savapage -- "${SP_SERVER_HOME}/bin/linux-x64/app-server" start

    ready_attempt=0
    until /usr/local/bin/healthcheck-savapage >/dev/null 2>&1; do
        ready_attempt=$((ready_attempt + 1))
        (( ready_attempt < 180 )) || fatal "SavaPage did not become healthy within 360 seconds"
        sleep 2
    done
    complete_upgrade_marker
    log "SavaPage, CUPS, and PostgreSQL are ready"

    while kill -0 "${CUPSD_PID}" 2>/dev/null \
        && test -s "${SP_PID}" \
        && test -d "/proc/$(cat "${SP_PID}")"; do
        sleep 2
    done
    fatal "A required service stopped unexpectedly"
}

main "$@"
