# Security and licensing

Default security posture: no privileged mode, host PID/IPC, GPU, Docker socket,
JMX, database publication, USB, RAW, CUPS admin, PAM, or AirPrint. Capabilities
are dropped and only CUPS/startup capabilities are restored. SavaPage launches
as UID/GID 1000; PostgreSQL uses its official non-root user. The root filesystem
cannot be read-only because SavaPage 1.6.0 lazily writes generated templates
under its installation tree.

The CUPS notifier is copied root-owned mode 0700 into CUPS's notifier directory.
It is colocated with SavaPage/CUPS to preserve push job-state delivery. The PAM
helper is root-owned mode 0511 without setuid by default. PAM mode changes it to
4511 and disables `no-new-privileges`; this materially expands attack surface.
The upstream systemd/SysV root tasks are never executed.

AirPrint grants host networking only to the Avahi discovery sidecar. USB grants
only selected devices unless the administrator chooses the entire USB bus.

SavaPage is AGPL-3.0-or-later. Operators who modify and offer it over a network
must meet AGPL source-offer obligations. Project scripts are GPL-3.0-only.
Debian packages retain their package licenses; PostgreSQL uses the PostgreSQL
License; OpenJDK uses GPLv2 with Classpath Exception; CUPS uses Apache-2.0 with
exceptions; Avahi is LGPL-2.1-or-later. See Debian copyright files inside the
image and [SavaPage dependency licenses](https://www.savapage.org/docs/licenses/dependencies.html).

CI builds amd64, generates an SPDX SBOM, and scans the image with Trivy. It does
not make upstream binaries more trustworthy: provenance rests on the official
URL plus mandatory SHA-256 because upstream publishes no detached installer
signature/checksum alongside 1.6.0.

