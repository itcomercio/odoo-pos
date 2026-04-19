SUMMARY = "Odoo POS hotkey mappings for triggerhappy"
DESCRIPTION = "Installs triggerhappy key bindings and a safe hook runner for custom POS actions"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    file://odoo-pos.conf \
    file://odoo-pos-hotkey-runner.sh \
    file://F4.sh \
    file://triggerhappy-root.conf \
"

RDEPENDS:${PN} = " \
    triggerhappy \
"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${sysconfdir}/triggerhappy/triggers.d
    install -m 0644 ${UNPACKDIR}/odoo-pos.conf ${D}${sysconfdir}/triggerhappy/triggers.d/odoo-pos.conf

    install -d ${D}${libexecdir}
    install -m 0755 ${UNPACKDIR}/odoo-pos-hotkey-runner.sh ${D}${libexecdir}/odoo-pos-hotkey-runner.sh

    install -d ${D}${sysconfdir}/triggerhappy/hooks
    install -m 0755 ${UNPACKDIR}/F4.sh ${D}${sysconfdir}/triggerhappy/hooks/F4.sh

    # systemd drop-in: run triggerhappy as root so it can write to /dev/usb/lp0
    install -d ${D}${systemd_system_unitdir}/triggerhappy.service.d
    install -m 0644 ${UNPACKDIR}/triggerhappy-root.conf \
        ${D}${systemd_system_unitdir}/triggerhappy.service.d/10-run-as-root.conf
}

FILES:${PN} += " \
    ${sysconfdir}/triggerhappy/triggers.d/odoo-pos.conf \
    ${libexecdir}/odoo-pos-hotkey-runner.sh \
    ${sysconfdir}/triggerhappy/hooks/F4.sh \
    ${systemd_system_unitdir}/triggerhappy.service.d/10-run-as-root.conf \
"
