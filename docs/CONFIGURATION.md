# Configuration

The entrypoint emits deterministic `SP_SRV_01...` properties without printing
their values. Managed properties cover ports, PostgreSQL, pool size, redirect,
and explicitly enabled X-Forwarded-For processing. Additional properties use
one `key=value` per line; database and managed listener keys are rejected.

Defaults are two CPUs, 4 GiB RAM, pool maximum 20, PostgreSQL
`max_connections=30`, `MaxJobs 500`, preserved job history, discarded job
files, RAW off, CUPS admin off, AirPrint off, PAM off, and no JMX publication.

LDAP is configured in the SavaPage Admin UI. The TrueNAS LDAP fields are
planning reminders because stable 1.6.0 does not expose a complete documented
environment contract for LDAP secrets. Do not put LDAP passwords in additional
properties.

Archive and journal remain below `/opt/savapage/server/data`. Do not relocate
temporary files, SafePages, archive, or journal across dataset mount boundaries:
SavaPage relies on same-filesystem atomic rename.

The upstream 1.6.0 template does not list the newer XFF keys. Treat reverse
proxy XFF as requiring acceptance testing; allowed proxy CIDRs are mandatory
and trusting all clients is rejected.

