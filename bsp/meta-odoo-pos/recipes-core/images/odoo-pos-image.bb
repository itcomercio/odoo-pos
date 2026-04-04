SUMMARY = "Custom Odoo POS image"
DESCRIPTION = "Custom image recipe for Odoo POS based on core-image-weston"
LICENSE = "MIT"

require recipes-graphics/images/core-image-weston.bb

inherit extrausers

IMAGE_BASENAME = "odoo-pos-image"

# Also generate a compressed tar rootfs artifact.
IMAGE_FSTYPES:append = " tar.zst"

# Suppress multiple-provider warning for weston-init.
PREFERRED_RPROVIDER_weston-init = "weston-init"

# Include Odoo container runtime, kiosk browser, and Chromium.
# odoo-container pulls in: podman, postgresql, postgresql-server, bash, shadow.
# iproute2-ss provides the ss command for network diagnostics (separate subpackage in Yocto).
IMAGE_INSTALL:append = " odoo-pos-kiosk chromium-ozone-wayland odoo-container iproute2 iproute2-ss"

# Enforce the final desired unit state in the generated rootfs.
# This is the most reliable place to do it: even if package postinst/presets
# auto-enable units during image creation, we disable them again in the final
# filesystem image and remove leftover wants-links explicitly.
disable_unused_pos_services() {
    for unit in \
        neard.service \
        bluetooth.service \
        avahi-daemon.service \
        systemd-networkd-wait-online.service \
        busybox-klogd.service \
        busybox-syslog.service \
        ip6tables.service \
    ; do
        if [ -e "${IMAGE_ROOTFS}${systemd_system_unitdir}/$unit" ] || \
           [ -e "${IMAGE_ROOTFS}${sysconfdir}/systemd/system/$unit" ]; then
            systemctl --root="${IMAGE_ROOTFS}" disable "$unit" >/dev/null 2>&1 || true
        fi

        # Remove any leftover symlink created by package postinst, Also=, Alias=,
        # or target wants/socket wants handling during rootfs creation.
        find "${IMAGE_ROOTFS}${sysconfdir}/systemd/system" -type l \( \
            -name "$unit" -o \
            -path "*/multi-user.target.wants/$unit" -o \
            -path "*/graphical.target.wants/$unit" -o \
            -path "*/network-online.target.wants/$unit" -o \
            -path "*/sockets.target.wants/$unit" \
        \) -delete 2>/dev/null || true
    done

    for unit in rpcbind.service rpcbind.socket podman.service podman.socket; do
        if [ -e "${IMAGE_ROOTFS}${systemd_system_unitdir}/$unit" ] || \
           [ -e "${IMAGE_ROOTFS}${sysconfdir}/systemd/system/$unit" ]; then
            systemctl --root="${IMAGE_ROOTFS}" disable "$unit" >/dev/null 2>&1 || true
        fi
        find "${IMAGE_ROOTFS}${sysconfdir}/systemd/system" -type l \( \
            -name "$unit" -o \
            -path "*/multi-user.target.wants/$unit" -o \
            -path "*/graphical.target.wants/$unit" -o \
            -path "*/network-online.target.wants/$unit" -o \
            -path "*/sockets.target.wants/$unit" \
        \) -delete 2>/dev/null || true
    done

    # systemd-networkd installs wait-online via network-online.target.wants.
    # Remove it explicitly to avoid boot delays on the kiosk.
    rm -f "${IMAGE_ROOTFS}${sysconfdir}/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
}
ROOTFS_POSTPROCESS_COMMAND:append = " disable_unused_pos_services;"

# Default root password: odoo
ROOT_PASSWORD_HASH = "\$6\$c6aQckAX4qXzO1vZ\$.GUniYswCC/RjUB5QCUTxnbM9g0.IhI4wKhtQa/hadwba368xN74WhFC3IhnUVwhk4zyg.J27dU2WZ2S.vsUQ0"

# Set the root shell to bash and provision a deterministic root password.
EXTRA_USERS_PARAMS = " \
	usermod -p '${ROOT_PASSWORD_HASH}' root; \
	usermod -s /bin/bash root; \
"
