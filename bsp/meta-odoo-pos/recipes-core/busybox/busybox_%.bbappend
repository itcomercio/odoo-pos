# Use journald only in the kiosk image; do not auto-enable BusyBox syslog/klogd.
SYSTEMD_AUTO_ENABLE:${PN}-syslog = "disable"

