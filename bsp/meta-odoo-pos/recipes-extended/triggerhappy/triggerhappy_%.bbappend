FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Workaround for Fedora Python 3.14 pseudo/fakeroot tar issue
inherit skip-fakeroot-tar

SRC_URI:append = " file://triggerhappy-root.conf"


do_install:append() {
    install -d ${D}${sysconfdir}/systemd/system/triggerhappy.service.d
    install -m 0644 ${UNPACKDIR}/triggerhappy-root.conf \
        ${D}${sysconfdir}/systemd/system/triggerhappy.service.d/99-run-as-root.conf
}

FILES:${PN}:append = " ${sysconfdir}/systemd/system/triggerhappy.service.d/99-run-as-root.conf"

