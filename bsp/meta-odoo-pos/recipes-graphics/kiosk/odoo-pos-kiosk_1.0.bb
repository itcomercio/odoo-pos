SUMMARY = "Odoo POS kiosk startup assets"
DESCRIPTION = "Weston kiosk configuration and auto-start browser launcher"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://weston-kiosk-env.conf \
    file://odoo-pos-kiosk.service \
    file://odoo-pos-kiosk-launcher.sh \
    file://index.html \
    file://psplash-systemd-override.conf \
    file://getty-override.conf \
"


inherit systemd

S = "${UNPACKDIR}"

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "odoo-pos-kiosk.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} += "bash weston weston-init"

do_install() {
    # Drop-in to force a stable XDG_RUNTIME_DIR=/run for the weston.service unit,
    # so both Weston and the kiosk launcher agree on where the Wayland socket lives.
    install -d ${D}${sysconfdir}/systemd/system/weston.service.d
    install -m 0644 ${UNPACKDIR}/weston-kiosk-env.conf \
        ${D}${sysconfdir}/systemd/system/weston.service.d/kiosk-env.conf

    # Disable psplash-systemd automatic quit — the kiosk launcher sends QUIT
    # to psplash manually so the boot splash stays until Chromium takes over.
    install -d ${D}${sysconfdir}/systemd/system/psplash-systemd.service.d
    install -m 0644 ${UNPACKDIR}/psplash-systemd-override.conf \
        ${D}${sysconfdir}/systemd/system/psplash-systemd.service.d/kiosk-override.conf

    # Disable getty on VT1-VT6 so no login prompt ever appears on screen.
    for vtnum in 1 2 3 4 5 6; do
        install -d ${D}${sysconfdir}/systemd/system/getty@tty${vtnum}.service.d
        install -m 0644 ${UNPACKDIR}/getty-override.conf \
            ${D}${sysconfdir}/systemd/system/getty@tty${vtnum}.service.d/kiosk-override.conf
    done

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/odoo-pos-kiosk.service ${D}${systemd_system_unitdir}/odoo-pos-kiosk.service

    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/odoo-pos-kiosk-launcher.sh ${D}${bindir}/odoo-pos-kiosk-launcher.sh

    install -d ${D}${datadir}/odoo-pos/kiosk
    install -m 0644 ${UNPACKDIR}/index.html ${D}${datadir}/odoo-pos/kiosk/index.html

    install -d ${D}/var/lib/odoo-pos/chromium-profile
}

FILES:${PN} += " \
    ${sysconfdir}/systemd/system/weston.service.d/kiosk-env.conf \
    ${sysconfdir}/systemd/system/psplash-systemd.service.d/kiosk-override.conf \
    ${sysconfdir}/systemd/system/getty@tty1.service.d/kiosk-override.conf \
    ${sysconfdir}/systemd/system/getty@tty2.service.d/kiosk-override.conf \
    ${sysconfdir}/systemd/system/getty@tty3.service.d/kiosk-override.conf \
    ${sysconfdir}/systemd/system/getty@tty4.service.d/kiosk-override.conf \
    ${sysconfdir}/systemd/system/getty@tty5.service.d/kiosk-override.conf \
    ${sysconfdir}/systemd/system/getty@tty6.service.d/kiosk-override.conf \
    ${systemd_system_unitdir}/odoo-pos-kiosk.service \
    ${bindir}/odoo-pos-kiosk-launcher.sh \
    ${datadir}/odoo-pos/kiosk/index.html \
    /var/lib/odoo-pos/chromium-profile \
"

