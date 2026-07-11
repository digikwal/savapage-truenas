# Architecture

## Decision

The deployment uses two containers:

```text
LAN clients/printers
        |
        | 8631/8632/8633; optional 9100, 631
        v
+-----------------------------------+       private bridge       +-------------+
| savapage                          |---------------------------->| postgres    |
|                                   |  PostgreSQL 5432 (internal) | PostgreSQL 17|
| PID 1 entrypoint                  |                             +-------------+
|  |- cupsd (local CUPS :631)       |
|  `- SavaPage (user savapage)      |
| CUPS notifier installed locally   |
+-----------------------------------+
        ^
        | optional host-network mDNS advertisement only
   +---------+
   | Avahi   |
   +---------+
```

SavaPage and CUPS remain in one container. A separate CUPS container was
rejected because SavaPage's supported behavior assumes local CUPS at
`localhost:631`, installs an executable into CUPS's notifier directory, and
uses push subscriptions for job/printer state. Splitting it would require
unverified changes to notifier delivery, Unix permissions, startup sequencing,
queue synchronization, and job-ID recovery. PostgreSQL is independent because
it has a clean network protocol and lifecycle boundary.

## Process and privilege model

The application image starts as root because CUPS must create scheduler files,
bind its local port, optionally access explicitly mapped USB devices, and the
entrypoint must correct narrowly scoped persistent-directory ownership. The
entrypoint never runs upstream systemd/SysV root tasks. It starts `cupsd` in
the foreground/background-managed container lifecycle and launches SavaPage
through its supplied script as the fixed `savapage` account.

Default mode:

- No privileged container, host PID, host IPC, Docker socket, or arbitrary
  host-root mount.
- All Linux capabilities are dropped except those proven necessary by the
  final runtime tests.
- `no-new-privileges` is enabled.
- `savapage-pam` is root-owned but has no setuid bit.
- CUPS is local-only and its web administration is not published.
- PostgreSQL runs as its official image-defined non-root account and is only on
  the private application network.

PAM mode is exceptional. Enabling it changes `savapage-pam` to root:root 4511,
creates `/etc/pam.d/savapage`, and requires `no-new-privileges` to be disabled
because that security option prevents setuid elevation. The TrueNAS template
renders that change only when `enable_pam_authentication` is true and emits a
security warning. LDAP does not require PAM mode.

## Persistence model

The logical locations are:

| Content | Container path |
| --- | --- |
| SavaPage configuration, encryption keys, SafePages | `/opt/savapage/server/data` |
| SavaPage logs | `/opt/savapage/server/logs` |
| CUPS configuration and queues | `/etc/cups` |
| CUPS job-ID/cache state | `/var/cache/cups` |
| CUPS spool and job metadata | `/var/spool/cups` |
| CUPS runtime state | `/var/lib/cups` |
| PostgreSQL data | `/var/lib/postgresql/data` |
| Optional archive | below SavaPage data parent |
| Optional journal | below SavaPage data parent |

SavaPage creates temporary files and atomically renames them into SafePages,
archive, and journal locations. Those locations must be on one filesystem.
Standalone Compose therefore uses one `savapage-data` volume for the complete
data tree, with archive and journal as subdirectories. The TrueNAS UI exposes
the locations but warns and rejects unsafe combinations where feasible; the
recommended layout is one parent host dataset with subdirectories, not separate
dataset mountpoints.

`/var/cache/cups` is always persistent and is never cleared by startup,
upgrade, or health logic. It contains CUPS `NextJobId` state that must remain in
sync with job IDs recorded in PostgreSQL.

## Configuration flow

The entrypoint validates environment, storage, port combinations, proxy CIDRs,
PAM security mode, and AirPrint/host-network compatibility before starting
services. It generates deterministic `SP_SRV_01`, `SP_SRV_02`, ... values for:

- listener host and HTTP/HTTPS/local HTTPS/RAW ports;
- HTTP-to-HTTPS redirect;
- PostgreSQL type, driver, URL, user, password, and connection pool;
- explicitly enabled X-Forwarded-For handling and allowed proxy CIDRs;
- administrator-provided additional server properties.

Environment variables override `server.properties`, which lets upgrades retain
administrator data while current deployment settings remain deterministic.
Secrets are never printed. Additional properties reject database password and
other managed keys to prevent ambiguous overrides.

## Readiness and shutdown

PostgreSQL uses `pg_isready`. SavaPage waits for PostgreSQL before starting.
CUPS health checks scheduler IPP response plus writability of its persistent
state. SavaPage health checks its process, a real HTTP(S) response, absence of
fatal startup markers, PostgreSQL readiness, and CUPS IPP response. Java gets a
long startup grace period.

PID 1 traps TERM/INT, requests a SavaPage clean shutdown through the supplied
script, terminates CUPS, and waits for both. Upgrade logic backs up critical
configuration, verifies the installed and target versions, applies the
installer over the top once, and only advances its marker after success.

## AirPrint

AirPrint is disabled by default. When enabled, a small Avahi sidecar uses host
networking so it can announce on the LAN; SavaPage and PostgreSQL remain on
bridge networking. The advertised hostname must resolve to the TrueNAS host,
and advertised ports are the actual published SavaPage host ports. IPv4 and
IPv6 can be independently disabled, but not both. Bridge-mode mDNS is rejected
rather than falsely advertised as working.

## USB printers

Specific device mapping is preferred. Advanced `/dev/bus/usb` mapping is
available but broader. Neither mode makes the container privileged. USB
identity and permissions can change after reconnect or host upgrades; network
IPP/IPPS printers remain the production recommendation.

## Upgrade and rollback boundary

Image builds contain one SavaPage release. A newer image performs the official
over-the-top install against persistent data only after creating a pre-upgrade
backup. Database migration remains SavaPage-controlled and is recorded with an
idempotent marker. Rollback means restoring the application-consistent
PostgreSQL dump and SavaPage/CUPS datasets taken before the upgrade, then
starting the previous image digest. Starting an old image against a migrated
database is not considered a safe rollback.
