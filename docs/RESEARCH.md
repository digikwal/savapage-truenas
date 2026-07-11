# Research

Inspected: 2026-07-11 (Europe/Amsterdam)

This document records the primary sources and repository examples used for the
SavaPage image, standalone deployment, and TrueNAS Community App.

## TrueNAS Apps conventions

The working copy of the official [TrueNAS Apps repository](https://github.com/truenas/apps)
was at commit `762d37522fbdc81880cbb13a8acf4aeab2ed845c` dated 2026-07-10.
It is the Docker Compose catalog, not the retired Kubernetes/Helm catalog.

Current app sources live at `ix-dev/community/<app>/` and contain:

- `app.yaml`: catalog metadata and independent semantic app-package version.
- `ix_values.yaml`: fixed image references and template constants. Image keys
  end in `_image` or `image`.
- `questions.yaml`: grouped UI schema. Passwords use `private: true`; ports,
  storage, host networking, devices, labels, and resource limits use current
  normalization references.
- `templates/docker-compose.yaml`: Jinja using the latest non-v1 rendering
  library. The inspected repository's newest library is 2.3.8.
- `templates/test_values/*.yaml`: complete render/deployment fixtures.
- `README.md`: deliberately short catalog description.

The renderer adds Compose security defaults, including dropping capabilities
and `no-new-privileges=true`, and automatically selects host networking when
`network.host_network` is true. Catalog validation is performed with
`.github/scripts/ci.py`; metadata and port checks use
`.github/scripts/generate_metadata.py` and `.github/scripts/port_validation.py`.
Generated `item.yaml`, catalog trains, and copied rendering-library content are
not hand-edited.

Repository contribution policy permits app work only below `ix-dev/` (or shared
library work below `library/`). For that reason this image project is maintained
separately and the catalog definition alone is added to
`ix-dev/community/savapage`.

### Current catalog examples inspected

- `zabbix`: PostgreSQL dependency helper, four application containers,
  internal networking, health dependencies, persistent PostgreSQL storage, and
  permission initialization.
- `paperless-ngx`: PostgreSQL plus Redis and optional containers, multiple
  persistent locations, user-selectable host paths/ixVolumes, and conditional
  services.
- `adguard-home`: host-network selection and warnings for a feature requiring
  broadcast/network-level behavior.
- `octoprint`: a list of specific host-to-container device mappings using the
  library device API.

These examples were inspected locally from the official repository at the
commit above. The implementation follows their library APIs but does not copy
obsolete Kubernetes-era patterns.

Sources:

- [TrueNAS Apps repository](https://github.com/truenas/apps)
- [TrueNAS Apps contribution guide](https://github.com/truenas/apps/blob/master/CONTRIBUTIONS.md)

## SavaPage release and installer

The stable release selected is **1.6.0-final**, published 2025-12-15. Version
1.7.0 material exists, but upstream release tracking still contains
pre-release/in-progress signals; it is not the conservative production pin.
The official installer is only published for Linux x86-64. Consequently this
project builds `linux/amd64` only and does not claim arm64 support.

Artifact:

```text
URL: https://www.savapage.org/download/installer/savapage-setup-1.6.0-final-linux-x64.bin
SHA-256: b5c388a35b707946ca8f4264605b6b252c6620769e2e32dbf910425fd381433c
Size shown upstream: 122407 KB
```

The SHA-256 above was computed from the official artifact on 2026-07-11.
Upstream does not publish a detached installer signature or checksum alongside
the file in its installer index. The image build therefore makes SHA-256
mandatory. OpenPGP verification cannot be made mandatory without an upstream
detached signature and documented release-signing key. CI checks the pinned
checksum and fails closed.

The installer is a POSIX self-extracting archive. `-n` installs
non-interactively and leaves root tasks for later. Inspection of the 1.6.0
archive found these root operations:

- `server/bin/linux-x64/roottasks`: sets `savapage-pam` owner root and mode
  4511, creates `/etc/pam.d/savapage`, installs systemd or SysV service files,
  starts the service, and prints first-run guidance.
- `providers/cups/linux-x64/roottasks`: copies `savapage-notifier` into the
  CUPS notifier directory with root-owned executable permissions and attempts
  to create a live SavaPage CUPS subscription.

The image deliberately does not execute either root-task script blindly.
Instead it copies the notifier during build, starts services under a container
supervisor/entrypoint, and only applies setuid plus PAM configuration when the
administrator explicitly enables PAM. systemd/SysV installation and host
service startup are omitted because the container has its own PID 1. The live
CUPS subscription remains SavaPage's responsibility after both services are
ready.

Sources:

- [Official installer index](https://www.savapage.org/download/installer/)
- [1.6.0 release notes](https://wiki.savapage.org/doku.php?id=release_notes:release_notes_1.6.0)
- [Installation process and root tasks](https://www.savapage.org/docs/manual/ch-install-on-linux.html)
- [Server installation](https://www.savapage.org/docs/manual/ch-install-download.html)
- [Upstream Docker guide](https://wiki.savapage.org/doku.php?id=howto:docker)

## Runtime requirements

SavaPage 1.6.0 requires Java 11 or newer. Java 17 LTS was chosen: it exceeds
the requirement, is available in supported Debian, and is the Java version
shown in recent upstream operational reports. The runtime base is Debian 12
slim, which remains supported and matches upstream's current Docker guidance.

SavaPage requires the fixed `savapage` account and `/opt/savapage`. Its CUPS
integration assumes local CUPS on port 631 and uses a CUPS event notifier for
push status. Job IDs are persisted both in SavaPage's database and CUPS cache;
deleting `/var/cache/cups` can reuse IDs and corrupt status association.

PostgreSQL is upstream's recommended production database. This project pins
PostgreSQL 17 and defaults the SavaPage c3p0 pool to 20 connections. PostgreSQL
is configured for at least pool + 10 administrative/reserved connections and
is never published by default.

Sources:

- [SavaPage system/install account](https://www.savapage.org/docs/manual/ch-install-create-user-account.html)
- [Advanced configuration and environment variables](https://www.savapage.org/docs/manual/ch-install-on-linux-advanced-config.html)
- [External database guidance](https://www.savapage.org/docs/manual/ch-external-db.html)
- [File locations and same-filesystem warning](https://www.savapage.org/docs/manual/app-file-locations.html)

## Networking, AirPrint, and CUPS

SavaPage's standard ports are HTTP/IPP 8631, HTTPS/IPPS 8632, local HTTPS
8633, RAW/PostScript 9100, and secure JMX 8639. CUPS uses 631. AirPrint/mDNS
uses UDP 5353.

Avahi discovery is link-local multicast. Ordinary Docker bridge publication
does not transparently place mDNS announcements on the physical LAN. The
supported AirPrint mode therefore requires an explicit host-network choice.
This can conflict with TrueNAS services and every SavaPage/CUPS port. Cross-VLAN
discovery requires a network mDNS reflector or equivalent routing design.

The generated Avahi service is based on SavaPage's bundled example and
advertises both `_ipp._tcp` and `_ipps._tcp`, `/printers/airprint`, and the
actual configured ports/hostname. IPv4 and IPv6 are independently selectable.

Sources:

- [IPP Everywhere and AirPrint](https://www.savapage.org/docs/manual/ch-savapage-as-printer.html)
- [CUPS configuration and job-ID requirements](https://www.savapage.org/docs/manual/ch-install-cups.html)

## Image provenance

The upstream Docker wiki points to `jboillot/savapage`, but that is a community
image, uses mutable/unpinned dependencies in the published example, embeds a
CUPS password in its Dockerfile, enables remote CUPS broadly, and runs the PAM
root task unconditionally. It is not used here.

This project builds its own image from the official checksum-pinned installer
at `ghcr.io/digikwal/savapage-truenas`. CI records OCI labels, emits an SPDX
SBOM, scans with Trivy, and publishes immutable version and commit tags. The
catalog must pin a released tag (and should pin a digest once the initial image
is published).

SavaPage is AGPL-3.0-or-later. The container also includes Debian-packaged
components under their respective Debian package licenses and the official
PostgreSQL image under the PostgreSQL License. Detailed obligations and links
are maintained in `docs/SECURITY.md`.
