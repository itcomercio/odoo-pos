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

# Include Odoo container runtime, kiosk browser and Chromium.
# odoo-container pulls in: podman, postgresql, postgresql-server, bash, shadow.
# Add local printing stack for USB receipts via Chromium kiosk printing.
# iproute2-ss provides the ss command for network diagnostics (separate subpackage in Yocto).
# Weston on-screen keyboard binary (/usr/libexec/weston-keyboard) is shipped
# by package 'weston' in poky master, not by a separate 'weston-keyboard' pkg.
# Extra diagnostics requested on target:
# - weston-info -> package weston
# - libinput    -> package libinput-bin
# - systemd-analyze -> package systemd-analyze
# Python app deps requested on target:
# - jsonify is provided by Flask itself (flask.jsonify)
# USB thermal printer support (Zebra / thermal receipt printers):
# - usbutils -> lsusb, usbhid-dump for diagnostics
# - libusb1 -> USB device library (v1.0 API)
# - odoo-pos-usb-printer-rules -> custom udev rules + diagnostic script
# - iotbox -> daemon de odoo-iotbox gestionado por systemd
# Console keyboard reliability on maintenance TTYs:
# - kbd + kbd-keymaps provide loadkeys and keymap files
# - locale-base-es-es adds es_ES locale support used by shell/apps
# Hardware hotkeys:
# - triggerhappy daemon + odoo-pos-hotkeys mappings (F1 -> custom hook)
IMAGE_INSTALL:append = " odoo-pos-kiosk chromium-ozone-wayland odoo-container iotbox iproute2 iproute2-ss weston libinput-bin systemd-analyze cups cups-filters python3-flask python3-requests python3-pyserial usbutils libusb1 odoo-pos-usb-printer-rules kbd kbd-keymaps locale-base-es-es triggerhappy odoo-pos-hotkeys"

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

    # Keep local print backend available for Chromium kiosk silent printing.
    for unit in cups.service cups.socket; do
        if [ -e "${IMAGE_ROOTFS}${systemd_system_unitdir}/$unit" ] || \
           [ -e "${IMAGE_ROOTFS}${sysconfdir}/systemd/system/$unit" ]; then
            systemctl --root="${IMAGE_ROOTFS}" enable "$unit" >/dev/null 2>&1 || true
        fi
    done

    # Enable triggerhappy for global hotkey handling from physical keyboards.
    if [ -e "${IMAGE_ROOTFS}${systemd_system_unitdir}/triggerhappy.service" ] || \
       [ -e "${IMAGE_ROOTFS}${sysconfdir}/systemd/system/triggerhappy.service" ]; then
        systemctl --root="${IMAGE_ROOTFS}" enable "triggerhappy.service" >/dev/null 2>&1 || true
    fi

    # systemd-networkd installs wait-online via network-online.target.wants.
    # Remove it explicitly to avoid boot delays on the kiosk.
    rm -f "${IMAGE_ROOTFS}${sysconfdir}/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"

    # Force deterministic Linux console mapping on the target (TTY mode).
    # This avoids layout drift with some USB keyboards where 'es' is not
    # applied early enough in boot.
    install -d "${IMAGE_ROOTFS}${sysconfdir}"
    cat > "${IMAGE_ROOTFS}${sysconfdir}/vconsole.conf" << 'EOF'
KEYMAP=es
FONT=eurlatgr
EOF
    systemctl --root="${IMAGE_ROOTFS}" enable "systemd-vconsole-setup.service" >/dev/null 2>&1 || true

    # Kiosk profile: keep tty1 reserved for Weston/Chromium to avoid visible
    # login flashes, but preserve local maintenance access on tty2.
    systemctl --root="${IMAGE_ROOTFS}" disable "getty@tty1.service" >/dev/null 2>&1 || true
    rm -f "${IMAGE_ROOTFS}${sysconfdir}/systemd/system/getty@tty1.service.d/kiosk-override.conf"

    systemctl --root="${IMAGE_ROOTFS}" enable "getty@tty2.service" >/dev/null 2>&1 || true
    install -d "${IMAGE_ROOTFS}${sysconfdir}/systemd/system/getty@tty2.service.d"
    cat > "${IMAGE_ROOTFS}${sysconfdir}/systemd/system/getty@tty2.service.d/kiosk-delay.conf" << 'EOF'
[Unit]
After=weston.service odoo-pos-kiosk.service

[Service]
ExecStartPre=
ExecStartPre=/usr/bin/loadkeys es
ExecStartPre=/bin/sleep 15
EOF

    # Disable extra VTs; tty2 remains available for offline diagnostics.
    for vtnum in 3 4 5 6; do
        systemctl --root="${IMAGE_ROOTFS}" disable "getty@tty${vtnum}.service" >/dev/null 2>&1 || true
        rm -f "${IMAGE_ROOTFS}${sysconfdir}/systemd/system/getty@tty${vtnum}.service.d/kiosk-override.conf"
    done
}
ROOTFS_POSTPROCESS_COMMAND:append = " disable_unused_pos_services;"

# Default root password: odoo
ROOT_PASSWORD_HASH = "\$6\$c6aQckAX4qXzO1vZ\$.GUniYswCC/RjUB5QCUTxnbM9g0.IhI4wKhtQa/hadwba368xN74WhFC3IhnUVwhk4zyg.J27dU2WZ2S.vsUQ0"

# Set the root shell to bash and provision a deterministic root password.
EXTRA_USERS_PARAMS = " \
	usermod -p '${ROOT_PASSWORD_HASH}' root; \
	usermod -s /bin/bash root; \
"
