SUMMARY = "Odoo POS kiosk startup assets"
DESCRIPTION = "Weston kiosk configuration and auto-start browser launcher"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://weston.ini \
    file://odoo-pos-kiosk.service \
    file://odoo-pos-kiosk-launcher.sh \
    file://index.html \
"


inherit systemd

S = "${UNPACKDIR}"

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "odoo-pos-kiosk.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} += "bash weston"

# Replace weston-init with our kiosk configuration
RCONFLICTS:${PN} += "weston-init"
RPROVIDES:${PN} += "weston-init"
RREPLACES:${PN} += "weston-init"

do_install() {
    install -d ${D}${sysconfdir}/xdg/weston
    install -m 0644 ${UNPACKDIR}/weston.ini ${D}${sysconfdir}/xdg/weston/weston.ini

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/odoo-pos-kiosk.service ${D}${systemd_system_unitdir}/odoo-pos-kiosk.service

    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/odoo-pos-kiosk-launcher.sh ${D}${bindir}/odoo-pos-kiosk-launcher.sh

    install -d ${D}${datadir}/odoo-pos/kiosk
    install -m 0644 ${UNPACKDIR}/index.html ${D}${datadir}/odoo-pos/kiosk/index.html
}

FILES:${PN} += " \
    ${sysconfdir}/xdg/weston/weston.ini \
    ${systemd_system_unitdir}/odoo-pos-kiosk.service \
    ${bindir}/odoo-pos-kiosk-launcher.sh \
    ${datadir}/odoo-pos/kiosk/index.html \
"

