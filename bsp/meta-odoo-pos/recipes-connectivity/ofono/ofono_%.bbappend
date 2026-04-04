# Keep oFono installed if pulled by deps, but never auto-enable its systemd unit.
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

