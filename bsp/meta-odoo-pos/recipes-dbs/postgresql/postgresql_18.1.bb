SUMMARY = "PostgreSQL 18.1 database server and client"
HOMEPAGE = "https://www.postgresql.org/"
SECTION = "databases"
LICENSE = "PostgreSQL"
LIC_FILES_CHKSUM = "file://COPYRIGHT;md5=08b6032a749e67f6e3de84ea8e466933"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = "https://ftp.postgresql.org/pub/source/v${PV}/postgresql-${PV}.tar.bz2 \
           file://postgresql.service \
           file://postgresql-initdb.service \
           file://postgresql-initdb.sh \
"
SRC_URI[sha256sum] = "ff86675c336c46e98ac991ebb306d1b67621ece1d06787beaade312c2c915d54"

DEPENDS = "openssl readline zlib icu bison-native flex-native perl-native"

inherit autotools pkgconfig systemd useradd

# Loadable backend modules (e.g. dict_snowball.so) resolve some symbols from
# the postgres executable at runtime. Ensure they are exported by the linker.
LDFLAGS:append = " -Wl,--export-dynamic"

# PostgreSQL release tarballs already ship a generated ./configure.
# Run configure directly to avoid autoreconf (which enforces autoconf 2.69).
do_configure() {
    oe_runconf
}

USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "--system --home /var/lib/postgresql --no-create-home --shell /bin/false postgres"

EXTRA_OECONF = " \
    --with-openssl \
    --with-system-tzdata=${datadir}/zoneinfo \
    --disable-rpath \
"

# Provide a server alias package so image recipes can keep using postgresql-server.
PACKAGES += "${PN}-server"
ALLOW_EMPTY:${PN}-server = "1"
RDEPENDS:${PN}-server = "${PN}"

RDEPENDS:${PN} += "shadow tzdata glibc-utils"

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "postgresql-initdb.service postgresql.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# PostgreSQL embeds build directory paths in some generated/parser artifacts.
# Keep QA enabled globally; skip only buildpaths for affected output packages.
INSANE_SKIP:${PN} += "buildpaths"
INSANE_SKIP:${PN}-dev += "buildpaths"
INSANE_SKIP:${PN}-staticdev += "buildpaths"
INSANE_SKIP:${PN}-src += "buildpaths"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/postgresql.service ${D}${systemd_system_unitdir}/postgresql.service
    install -m 0644 ${UNPACKDIR}/postgresql-initdb.service ${D}${systemd_system_unitdir}/postgresql-initdb.service

    install -d ${D}${libexecdir}
    install -m 0755 ${UNPACKDIR}/postgresql-initdb.sh ${D}${libexecdir}/postgresql-initdb.sh

    install -d ${D}/var/lib/postgresql/data
    chmod 0700 ${D}/var/lib/postgresql/data
}

FILES:${PN} += " \
    ${systemd_system_unitdir}/postgresql.service \
    ${systemd_system_unitdir}/postgresql-initdb.service \
    ${libexecdir}/postgresql-initdb.sh \
    /var/lib/postgresql \
"
