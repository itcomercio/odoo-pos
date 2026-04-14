SUMMARY = "Odoo POS kiosk startup assets"
DESCRIPTION = "Weston kiosk configuration and auto-start Chromium browser launcher"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://weston-kiosk-env.conf \
    file://weston-readiness.conf \
    file://odoo-pos-kiosk.service \
    file://odoo-pos-kiosk-wait-wayland.conf \
    file://odoo-pos-kiosk-launcher.sh \
    file://index.html \
    file://Official_Odoo_logo.svg \
    file://psplash-systemd-override.conf \
    file://psplash-progress-helper.sh \
    file://getty-override.conf \
    file://chromium-policy.json \
"

inherit systemd

S = "${UNPACKDIR}"

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "odoo-pos-kiosk.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# Chromium-only kiosk (no WPE, no cog variable logic)
RDEPENDS:${PN} += "bash weston weston-init chromium-ozone-wayland seatd"

do_install() {
    # Drop-in to force a stable XDG_RUNTIME_DIR=/run for the weston.service unit,
    # so both Weston and the kiosk launcher agree on where the Wayland socket lives.
    install -d ${D}${sysconfdir}/systemd/system/weston.service.d
    install -m 0644 ${UNPACKDIR}/weston-kiosk-env.conf \
        ${D}${sysconfdir}/systemd/system/weston.service.d/kiosk-env.conf
    install -m 0644 ${UNPACKDIR}/weston-readiness.conf \
        ${D}${sysconfdir}/systemd/system/weston.service.d/10-readiness.conf

    install -d ${D}${sysconfdir}/systemd/system/odoo-pos-kiosk.service.d
    install -m 0644 ${UNPACKDIR}/odoo-pos-kiosk-wait-wayland.conf \
        ${D}${sysconfdir}/systemd/system/odoo-pos-kiosk.service.d/10-wait-wayland.conf

    # Override psplash-systemd helper so we keep systemd-driven progress updates
    # without sending QUIT automatically at 100%.
    install -d ${D}${sysconfdir}/systemd/system/psplash-systemd.service.d
    install -m 0644 ${UNPACKDIR}/psplash-systemd-override.conf \
        ${D}${sysconfdir}/systemd/system/psplash-systemd.service.d/kiosk-override.conf

    # Disable getty only on VT1, reserved for Weston/kiosk.
    # Keep tty2+ available for maintenance virtual terminals.
    install -d ${D}${sysconfdir}/systemd/system/getty@tty1.service.d
    install -m 0644 ${UNPACKDIR}/getty-override.conf \
        ${D}${sysconfdir}/systemd/system/getty@tty1.service.d/kiosk-override.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/odoo-pos-kiosk.service ${D}${systemd_system_unitdir}/odoo-pos-kiosk.service

    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/odoo-pos-kiosk-launcher.sh ${D}${bindir}/odoo-pos-kiosk-launcher.sh
    install -m 0755 ${UNPACKDIR}/psplash-progress-helper.sh ${D}${bindir}/psplash-progress-helper.sh

    install -d ${D}${datadir}/odoo-pos/kiosk
    install -m 0644 ${UNPACKDIR}/index.html ${D}${datadir}/odoo-pos/kiosk/index.html
    install -m 0644 ${UNPACKDIR}/Official_Odoo_logo.svg ${D}${datadir}/odoo-pos/kiosk/Official_Odoo_logo.svg

    # Chromium managed policy: disable translation UI and credential-save prompts.
    install -d ${D}${sysconfdir}/chromium/policies/managed
    install -m 0644 ${UNPACKDIR}/chromium-policy.json \
        ${D}${sysconfdir}/chromium/policies/managed/odoo-pos.json

    # Compatibility path used by some Chromium builds/wrappers.
    install -d ${D}${sysconfdir}/chromium-browser/policies/managed
    install -m 0644 ${UNPACKDIR}/chromium-policy.json \
        ${D}${sysconfdir}/chromium-browser/policies/managed/odoo-pos.json

    install -d ${D}/var/lib/odoo-pos/chromium-profile
}

FILES:${PN} += " \
    ${sysconfdir}/systemd/system/weston.service.d/kiosk-env.conf \
    ${sysconfdir}/systemd/system/weston.service.d/10-readiness.conf \
    ${sysconfdir}/systemd/system/odoo-pos-kiosk.service.d/10-wait-wayland.conf \
    ${sysconfdir}/systemd/system/psplash-systemd.service.d/kiosk-override.conf \
    ${sysconfdir}/systemd/system/getty@tty1.service.d/kiosk-override.conf \
    ${systemd_system_unitdir}/odoo-pos-kiosk.service \
    ${bindir}/odoo-pos-kiosk-launcher.sh \
    ${bindir}/psplash-progress-helper.sh \
    ${datadir}/odoo-pos/kiosk/index.html \
    ${datadir}/odoo-pos/kiosk/Official_Odoo_logo.svg \
    ${sysconfdir}/chromium/policies/managed/odoo-pos.json \
    ${sysconfdir}/chromium-browser/policies/managed/odoo-pos.json \
    /var/lib/odoo-pos/chromium-profile \
"
