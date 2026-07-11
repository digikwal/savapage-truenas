#!/bin/bash
set -eu
set -o pipefail

require() {
    local name=$1
    test -n "${!name:-}" || {
        echo "Required environment variable ${name} is empty" >&2
        exit 1
    }
}

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

require AIRPRINT_SERVICE_NAME
require AIRPRINT_HOSTNAME
require AIRPRINT_HTTPS_PORT
if test "${AIRPRINT_ENABLE_HTTP:-true}" = true; then require AIRPRINT_HTTP_PORT; fi
if test "${AVAHI_ENABLE_IPV4:-yes}" != yes && test "${AVAHI_ENABLE_IPV6:-yes}" != yes; then
    echo 'At least one of Avahi IPv4 or IPv6 must be enabled' >&2
    exit 1
fi

install -d -m 0755 /run/dbus /etc/avahi/services
cp /usr/share/savapage/avahi-daemon.conf /etc/avahi/avahi-daemon.conf
sed -i \
    -e "s/^#\?host-name=.*/host-name=${AIRPRINT_HOSTNAME%%.*}/" \
    -e "s/^use-ipv4=.*/use-ipv4=${AVAHI_ENABLE_IPV4:-yes}/" \
    -e "s/^use-ipv6=.*/use-ipv6=${AVAHI_ENABLE_IPV6:-yes}/" \
    /etc/avahi/avahi-daemon.conf

{
    printf '%s\n' '<?xml version="1.0" standalone="no"?><!DOCTYPE service-group SYSTEM "avahi-service.dtd">' '<service-group>'
    printf '  <name replace-wildcards="yes">%s</name>\n' "$(xml_escape "${AIRPRINT_SERVICE_NAME}")"
    printf '%s\n' '  <service>' '    <type>_ipps._tcp</type>' '    <subtype>_universal._sub._ipps._tcp</subtype>'
    printf '    <port>%s</port>\n' "${AIRPRINT_HTTPS_PORT}"
    printf '%s\n' '    <txt-record>rp=printers/airprint</txt-record>' '    <txt-record>ty=SavaPage Virtual Printer</txt-record>' '    <txt-record>pdl=application/pdf,application/postscript,image/urf,image/jpeg,image/pwg-raster</txt-record>' '    <txt-record>URF=none</txt-record>' '    <txt-record>Color=T</txt-record>' '    <txt-record>Duplex=F</txt-record>' '  </service>'
    if test "${AIRPRINT_ENABLE_HTTP:-true}" = true; then
        printf '%s\n' '  <service>' '    <type>_ipp._tcp</type>' '    <subtype>_universal._sub._ipp._tcp</subtype>'
        printf '    <port>%s</port>\n' "${AIRPRINT_HTTP_PORT}"
        printf '%s\n' '    <txt-record>rp=printers/airprint</txt-record>' '    <txt-record>ty=SavaPage Virtual Printer</txt-record>' '    <txt-record>pdl=application/pdf,application/postscript,image/urf,image/jpeg,image/pwg-raster</txt-record>' '    <txt-record>URF=none</txt-record>' '  </service>'
    fi
    printf '%s\n' '</service-group>'
} > /etc/avahi/services/savapage.service

dbus-daemon --system --fork
exec avahi-daemon --no-chroot --debug

