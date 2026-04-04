# Podman is used by scripts/services, but its own system units should stay disabled
# in kiosk deployments.
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

