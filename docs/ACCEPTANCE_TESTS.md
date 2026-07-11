# Manual acceptance checklist

- [ ] IPP/IPPS network printer queue prints and reports completion.
- [ ] JetDirect/AppSocket printer prints supported PostScript.
- [ ] LPD queue prints and reports completion.
- [ ] Driverless IPP Everywhere attributes are correct.
- [ ] AirPrint is discovered from macOS/iOS on IPv4 and IPv6.
- [ ] Cross-VLAN behavior is tested with the site's reflector.
- [ ] Specific USB printer survives reconnect/reboot or limitation is accepted.
- [ ] LDAP synchronization and authentication work; PAM remains off if unused.
- [ ] Restart/container recreation preserves keys, queues, job IDs, and data.
- [ ] TrueNAS app update succeeds from a tested backup.
- [ ] Dataset snapshot and clean restore pass the eight restore checks.
- [ ] TrueNAS maintenance interruption and recovery are understood.

