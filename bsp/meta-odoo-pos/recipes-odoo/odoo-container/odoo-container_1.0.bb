SUMMARY = "Odoo runtime via OCI container (Podman)"
DESCRIPTION = "Runs Odoo in a container on top of host PostgreSQL"
HOMEPAGE = "https://www.odoo.com"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    file://odoo-image.tar;unpack=0 \
    file://odoo-container.env \
    file://odoo.conf \
    file://odoo-container-launch.sh \
    file://odoo-container-import.service \
    file://odoo-container-import.sh \
    file://odoo.service \
    file://postgresql-odoo-setup.service \
    file://postgresql-odoo-setup.sh \
    file://containers.conf \
"

inherit systemd useradd

S = "${UNPACKDIR}"

# The OCI image tarball is a pre-built opaque blob; skip QA checks on it.
INSANE_SKIP:${PN} += "already-stripped"

USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "--system odoo"
USERADD_PARAM:${PN} = " \
    --system \
    --home /var/lib/odoo \
    --create-home \
    --shell /bin/false \
    --gid odoo \
    odoo \
"

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = " \
    odoo-container-import.service \
    postgresql-odoo-setup.service \
    odoo.service \
"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = " \
    podman \
    fuse-overlayfs \
    postgresql \
    postgresql-server \
    shadow \
    bash \
"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${sysconfdir}/odoo
    install -m 0640 ${UNPACKDIR}/odoo.conf ${D}${sysconfdir}/odoo/odoo.conf

    install -d ${D}${sysconfdir}/default
    install -m 0644 ${UNPACKDIR}/odoo-container.env ${D}${sysconfdir}/default/odoo-container

    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/odoo-container-launch.sh ${D}${bindir}/odoo-container-launch.sh

    install -d ${D}${libexecdir}
    install -m 0755 ${UNPACKDIR}/odoo-container-import.sh ${D}${libexecdir}/odoo-container-import.sh
    install -m 0755 ${UNPACKDIR}/postgresql-odoo-setup.sh ${D}${libexecdir}/postgresql-odoo-setup.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/odoo-container-import.service ${D}${systemd_system_unitdir}/odoo-container-import.service
    install -m 0644 ${UNPACKDIR}/odoo.service ${D}${systemd_system_unitdir}/odoo.service
    install -m 0644 ${UNPACKDIR}/postgresql-odoo-setup.service ${D}${systemd_system_unitdir}/postgresql-odoo-setup.service

    install -d ${D}${sysconfdir}/containers/containers.conf.d
    install -m 0644 ${UNPACKDIR}/containers.conf ${D}${sysconfdir}/containers/containers.conf.d/odoo-pos.conf

    install -d ${D}${localstatedir}/lib/containers/tmp
    install -d ${D}${localstatedir}/lib/containers/storage

    install -d ${D}${localstatedir}/lib/odoo
    install -d ${D}${localstatedir}/lib/odoo/log

    # OCI image tarball — podman load on first boot via odoo-container-import.service.
    install -m 0644 ${UNPACKDIR}/odoo-image.tar ${D}${localstatedir}/lib/odoo/odoo-container.tar

    # Disable selected Podman user units via preset (do not mask), so
    # systemctl preset-all in do_rootfs does not error out on masked units.
    install -d ${D}${libdir}/systemd/user-preset
    cat > ${D}${libdir}/systemd/user-preset/90-odoo-pos.preset << 'EOF'
# Odoo POS: avoid slow Podman user-unit startup path on normal boots
# (we run Odoo via system unit odoo.service).
disable podman-auto-update.service
disable podman-auto-update.timer
disable podman-clean-transient.service
disable podman-restart.service
disable podman.service
disable podman.socket
EOF

    # Disable unused system services by preset (do not mask), so preset-all
    # can process units cleanly during rootfs creation.
    install -d ${D}${libdir}/systemd/system-preset
    cat > ${D}${libdir}/systemd/system-preset/90-odoo-pos-system.preset << 'EOF'
# Odoo POS: disable services not needed in the kiosk appliance profile.
disable ofono.service
disable rpcbind.service
disable rpcbind.socket
disable podman.service
disable podman.socket
disable avahi-daemon.service
disable bluetooth.service
disable neard.service
disable systemd-networkd-wait-online.service
disable busybox-klogd.service
disable busybox-syslog.service
disable ip6tables.service
disable iptables.service
EOF
}

pkg_postinst:${PN}() {
    install -d "$D/var/lib/odoo/log"
    chown -R odoo:odoo "$D/var/lib/odoo"
    chown root:odoo "$D/etc/odoo/odoo.conf"
}

FILES:${PN} += " \
    ${sysconfdir}/odoo/odoo.conf \
    ${sysconfdir}/default/odoo-container \
    ${sysconfdir}/containers/containers.conf.d/odoo-pos.conf \
    ${localstatedir}/lib/containers \
    ${bindir}/odoo-container-launch.sh \
    ${systemd_system_unitdir}/odoo-container-import.service \
    ${systemd_system_unitdir}/odoo.service \
    ${systemd_system_unitdir}/postgresql-odoo-setup.service \
    ${libexecdir}/odoo-container-import.sh \
    ${libexecdir}/postgresql-odoo-setup.sh \
    ${localstatedir}/lib/odoo \
    ${libdir}/systemd/user-preset/90-odoo-pos.preset \
    ${libdir}/systemd/system-preset/90-odoo-pos-system.preset \
"
