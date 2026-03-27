FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " file://weston.ini"

# Override weston-init default config to force kiosk shell.
do_install:append() {
    install -d ${D}${sysconfdir}/xdg/weston
    install -m 0644 ${UNPACKDIR}/weston.ini ${D}${sysconfdir}/xdg/weston/weston.ini
}

