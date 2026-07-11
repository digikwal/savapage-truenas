# USB printers

USB access is off by default. Prefer a specific device such as `/dev/usb/lp0`.
The advanced `/dev/bus/usb` mapping exposes an entire bus and should be used
only when the printer/backend cannot use a narrower device.

Identify and validate a device on the host and in the container:

```sh
lsusb
docker compose exec savapage lsusb
docker compose exec savapage /usr/lib/cups/backend/usb
```

USB bus/device numbers and permissions may change after reconnect, reboot,
TrueNAS update, or hardware replacement. Device passthrough increases coupling
to the host. The app does not enable privileged mode merely for USB. Test job
submission and status notification after every host/hardware change. Network
IPP/IPPS printers are preferred in production.

