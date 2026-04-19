SUMMARY = "Odoo IoTBox service"
DESCRIPTION = "Installs odoo-iotbox from GitHub and runs iotbox.py as a systemd daemon"
HOMEPAGE = "https://github.com/itcomercio/odoo-iotbox"
LICENSE = "CLOSED"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    git://github.com/itcomercio/odoo-iotbox.git;branch=main;protocol=https \
    file://iotbox.service \
    file://iotbox.env \
"

PV = "1.0+git${SRCPV}"
SRCREV = "7f747050461a84f652ff84117c544f4f75790a07"
BB_GIT_SHALLOW = "1"


inherit systemd

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "iotbox.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = " \
    python3-core \
    python3-modules \
    python3-requests \
    python3-pyserial \
"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}/opt/iotbox
    cp -R ${S}/. ${D}/opt/iotbox/
    rm -rf ${D}/opt/iotbox/.git

    install -d ${D}${sysconfdir}/iotbox
    install -m 0644 ${UNPACKDIR}/iotbox.env ${D}${sysconfdir}/iotbox/iotbox.env

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/iotbox.service ${D}${systemd_system_unitdir}/iotbox.service
}

FILES:${PN} += " \
    /opt/iotbox \
    ${sysconfdir}/iotbox/iotbox.env \
    ${systemd_system_unitdir}/iotbox.service \
"
