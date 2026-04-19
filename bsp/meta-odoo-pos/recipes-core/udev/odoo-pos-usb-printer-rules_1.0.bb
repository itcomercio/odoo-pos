SUMMARY = "Odoo POS USB Printer udev rules"
DESCRIPTION = "udev rules for USB thermal printer detection and permissions"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${THISDIR}/../../COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

FILESEXTRAPATHS:prepend := "${THISDIR}:"

SRC_URI = "file://files/99-odoo-pos-usb-printer.rules file://files/check-printer-support.sh"

# Shell script requires bash at runtime
RDEPENDS:${PN} = "bash"

do_install() {
    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${UNPACKDIR}/files/99-odoo-pos-usb-printer.rules ${D}${sysconfdir}/udev/rules.d/

    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/files/check-printer-support.sh ${D}${bindir}/check-printer-support
}

FILES:${PN} = "${sysconfdir}/udev/rules.d/99-odoo-pos-usb-printer.rules ${bindir}/check-printer-support"



