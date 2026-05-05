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
SRCREV = "${AUTOREV}"
BB_GIT_SHALLOW = "1"

IOTBOX_ADDONS_DEST = "${localstatedir}/lib/odoo/custom_addons"
IOTBOX_ADDONS_SRC = "${S}/addon"


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

    install -d ${D}${IOTBOX_ADDONS_DEST}
    if [ -d "${IOTBOX_ADDONS_SRC}" ]; then
        for module_dir in "${IOTBOX_ADDONS_SRC}"/*; do
            [ -d "$module_dir" ] || continue
            [ -f "$module_dir/__manifest__.py" ] || continue
            cp -R "$module_dir" ${D}${IOTBOX_ADDONS_DEST}/
        done
    fi

    # Keep addons only in the Odoo custom addons volume path.
    rm -rf ${D}/opt/iotbox/addon

    install -d ${D}${sysconfdir}/iotbox
    install -m 0644 ${UNPACKDIR}/iotbox.env ${D}${sysconfdir}/iotbox/iotbox.env

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/iotbox.service ${D}${systemd_system_unitdir}/iotbox.service
}

FILES:${PN} += " \
    /opt/iotbox \
    ${IOTBOX_ADDONS_DEST} \
    ${sysconfdir}/iotbox/iotbox.env \
    ${systemd_system_unitdir}/iotbox.service \
"
