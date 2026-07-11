# Networking and AirPrint

| Service | Internal port | Default publication |
| --- | ---: | --- |
| HTTP/IPP | 8631/tcp | localhost in Compose; configurable in TrueNAS |
| HTTPS/IPPS | 8632/tcp | localhost in Compose; configurable in TrueNAS |
| Local HTTPS | 8633/tcp | localhost in Compose; configurable in TrueNAS |
| RAW PostScript | 9100/tcp | disabled |
| CUPS admin | 631/tcp | disabled |
| PostgreSQL | 5432/tcp | never published |
| Secure JMX | 8639/tcp | never published |
| mDNS | 5353/udp | optional host-network Avahi sidecar |

CUPS listens only on localhost unless administration is explicitly enabled.
Browsing/publication is off, remote printer browsing is disabled, and the
policy limits print submission to localhost. Each proxy queue still needs
`Shared Yes` locally so the `savapage` account can use it.

AirPrint advertises `/printers/airprint` through `_ipp._tcp` and `_ipps._tcp`
using the configured published ports. The hostname must resolve to the NAS LAN
address. Host networking may collide with another Avahi daemon or UDP 5353.
mDNS is link-local and does not transparently traverse VLANs; use a network
reflector when required. Validate from a LAN client with:

```sh
avahi-browse -a -t
ippfind _ipp._tcp _ipps._tcp
ipptool -tv ipps://HOST:PORT/printers/airprint get-printer-attributes.test
```

