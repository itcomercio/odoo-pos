SUMMARY = "Odoo 19.0 Community Edition"
DESCRIPTION = "Open source ERP and Point of Sale business application suite"
HOMEPAGE = "https://www.odoo.com"
SECTION = "business"
LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=8cebefe2150928cbee18cfd2a4e63c03"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    git://github.com/odoo/odoo.git;protocol=https;branch=19.0;name=odoo \
    file://odoo.conf \
    file://odoo.service \
    file://odoo-conda-unpack.service \
    file://postgresql-odoo-setup.service \
    file://postgresql-odoo-setup.sh \
"

BB_GIT_SHALLOW:pn-odoo = "1"
SRCREV = "${AUTOREV}"
PV = "19.0+git${SRCPV}"

# NOTE: do NOT set S for git recipes — oe-core's bitbake.conf handles it automatically.

# ── Why Miniconda ─────────────────────────────────────────────────────────────
# Odoo's requirements.txt uses python_version markers (e.g. "< '3.13'") that
# silently skip packages like lxml, gevent, Pillow on Python 3.14 (the host).
# By pinning to Python 3.12 (Odoo 19.0's target version) inside a conda env,
# all markers resolve correctly and every package has a pre-built binary wheel.
# conda-pack produces a relocatable tarball; conda-unpack fixes paths on first
# boot — no compilation or internet access is needed on the target device.
do_compile[network] = "1"

inherit systemd useradd

USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "--system odoo"
USERADD_PARAM:${PN} = " \
    --system \
    --home /home/odoo \
    --create-home \
    --shell /bin/false \
    --gid odoo \
    odoo \
"

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = " \
    postgresql-odoo-setup.service \
    odoo-conda-unpack.service \
    odoo.service \
"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# The conda env bundles Python + all C libs; only PostgreSQL and bash are needed
# at runtime from the BSP side.
RDEPENDS:${PN} = " \
    postgresql \
    postgresql-server \
    bash \
"

do_configure[noexec] = "1"

# The bundled conda environment ships its own runtime libs (libstdc++, libgcc,
# ICU, etc.) under /opt/odoo-env/lib. We don't want this package to advertise
# those as global shlib providers, otherwise it conflicts with core packages
# like libgcc/libstdc++ during do_package.
EXCLUDE_FROM_SHLIBS = "1"

do_compile() {
    # ── Restore standard host tool directories in PATH ────────────────────────
    # Yocto sanitises PATH for reproducibility, removing /usr/bin, /bin, etc.
    # The Miniconda installer calls 'df' (without a full path) to check disk
    # space — it fails with "df: command not found" and reports "-50 MB free",
    # which causes an immediate abort.  Adding the standard dirs back makes df
    # and other POSIX tools available for the installer without breaking the
    # rest of the Yocto build (we still use absolute paths for our own calls).
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

    CONDA_DIR="${WORKDIR}/miniconda"
    CONDA_ENV_NAME="odoo"
    CONDA_PY="${CONDA_DIR}/bin/python"

    # ── 1. Install Miniconda (idempotent) ─────────────────────────────────────
    if [ ! -x "${CONDA_DIR}/bin/conda" ]; then
        # Remove any partial/failed previous installation before retrying.
        rm -rf "${CONDA_DIR}"
        bbnote "Downloading Miniconda installer..."
        if [ -x /usr/bin/curl ]; then
            /usr/bin/curl -fsSL \
                "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" \
                -o "${WORKDIR}/miniconda.sh"
        else
            /usr/bin/wget -q \
                "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" \
                -O "${WORKDIR}/miniconda.sh"
        fi
        bash "${WORKDIR}/miniconda.sh" -b -p "${CONDA_DIR}"
        rm -f "${WORKDIR}/miniconda.sh"
    else
        bbnote "Miniconda already present at ${CONDA_DIR}, skipping download."
    fi

    # ── 2. Create conda environment with Python 3.12 (idempotent) ────────────
    if [ ! -d "${CONDA_DIR}/envs/${CONDA_ENV_NAME}" ]; then
        bbnote "Creating conda environment '${CONDA_ENV_NAME}' (Python 3.12)..."
        "${CONDA_PY}" "${CONDA_DIR}/bin/conda" create -y \
            -n "${CONDA_ENV_NAME}" \
            python=3.12 pip wheel \
            -c conda-forge --override-channels
    else
        bbnote "Conda env '${CONDA_ENV_NAME}' already exists, skipping creation."
    fi

    # ── 3. Install Odoo Python deps via the conda-env pip ─────────────────────
    # Python 3.12: markers resolve correctly. We still force binary-only wheels
    # to avoid any C extension build under Yocto's cross-compilation env.
    # - psycopg2 -> psycopg2-binary (all variants/markers)
    # - drop python-ldap (optional for LDAP auth, not needed for POS baseline)
    # - drop ofxparse/rjsmin/vobject/num2words pinned lines
    #   (handled separately with >= outside the binary-only block)
    CONDA_PIP="${CONDA_DIR}/envs/${CONDA_ENV_NAME}/bin/pip"

    sed -E \
        -e 's/^psycopg2([<>=!~].*)?$/psycopg2-binary\1/' \
        -e '/^python-ldap([<>=!~].*)?([[:space:]]*;.*)?$/d' \
        -e '/^ofxparse([<>=!~].*)?([[:space:]]*;.*)?$/d' \
        -e '/^rjsmin([<>=!~].*)?([[:space:]]*;.*)?$/d' \
        -e '/^vobject([<>=!~].*)?([[:space:]]*;.*)?$/d' \
        -e '/^num2words([<>=!~].*)?([[:space:]]*;.*)?$/d' \
        "${S}/requirements.txt" > "${WORKDIR}/requirements-patched.txt"

    # Prevent pip from inheriting Yocto cross-toolchain variables.
    unset CC CXX CPP LD LDSHARED AR AS RANLIB STRIP OBJCOPY OBJDUMP NM
    unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS PKG_CONFIG PKG_CONFIG_PATH

    bbnote "Installing Odoo Python dependencies..."
    "${CONDA_PIP}" install \
        --prefer-binary \
        --only-binary=:all: \
        --no-cache-dir \
        -r "${WORKDIR}/requirements-patched.txt"

    # Some pure-python deps are frequently unavailable as wheels in strict pinned
    # versions (or their transitive deps are sdist-only). Install them separately
    # without --only-binary and with relaxed minimum versions.
    "${CONDA_PIP}" install \
        --no-cache-dir \
        "ofxparse>=0.21" \
        "rjsmin>=1.2.2" \
        "vobject>=0.9.7" \
        "num2words>=0.5.13" \
        "docopt>=0.6.2"

    # ── 4. Install conda-pack and pack the environment ────────────────────────
    # Install conda-pack via pip to avoid Anaconda default channel ToS checks
    # (repo.anaconda.com). We already have a working pip path in this env.
    # conda-pack creates a relocatable tarball; conda-unpack (included inside)
    # patches absolute paths on first boot on the target device.
    bbnote "Installing conda-pack (via pip)..."
    "${CONDA_PIP}" install --no-cache-dir "conda-pack>=0.8.0"

    bbnote "Packing conda environment (may take a few minutes)..."
    rm -f "${WORKDIR}/odoo-env.tar.gz"
    "${CONDA_PIP%/pip}/python" "${CONDA_PIP%/pip}/conda-pack" \
        -p "${CONDA_DIR}/envs/${CONDA_ENV_NAME}" \
        -o "${WORKDIR}/odoo-env.tar.gz" \
        --ignore-missing-files
    bbnote "conda-pack done: $(du -sh ${WORKDIR}/odoo-env.tar.gz | cut -f1)"
}

do_install() {
    # ── Odoo source → /opt/odoo ───────────────────────────────────────────────
    install -d "${D}/opt/odoo"
    cp -r "${S}/." "${D}/opt/odoo/"

    # Remove source-control and distro packaging metadata not needed at runtime.
    # These files pull host-tool shebang deps into QA (/usr/bin/perl, /usr/bin/make,
    # /usr/bin/python) and should not ship in the target image.
    rm -rf "${D}/opt/odoo/.git" "${D}/opt/odoo/debian" "${D}/opt/odoo/doc/cla"

    # ── Conda env → /opt/odoo-env ─────────────────────────────────────────────
    # Unpack the conda-pack tarball. The included conda-unpack script will fix
    # all absolute paths at first-boot time via odoo-conda-unpack.service.
    install -d "${D}/opt/odoo-env"
    # Avoid preserving host uid/gid from conda-pack tarball entries.
    tar --no-same-owner -xzf "${WORKDIR}/odoo-env.tar.gz" -C "${D}/opt/odoo-env"

    # ── Configuration ──────────────────────────────────────────────────────────
    install -d "${D}${sysconfdir}/odoo"
    install -m 0640 "${UNPACKDIR}/odoo.conf" "${D}${sysconfdir}/odoo/odoo.conf"

    # Keep logs under /var/lib to avoid /var/log symlink and /var/volatile QA
    # policies, while still providing a writable persistent location.
    install -d "${D}${localstatedir}/lib/odoo/log"
    install -d "${D}/home/odoo"
    install -d "${D}/home/odoo/.local"

    # ── Helper scripts ─────────────────────────────────────────────────────────
    install -d "${D}${libexecdir}"
    install -m 0755 "${UNPACKDIR}/postgresql-odoo-setup.sh" \
        "${D}${libexecdir}/postgresql-odoo-setup.sh"

    # ── Systemd unit files ─────────────────────────────────────────────────────
    install -d "${D}${systemd_system_unitdir}"
    install -m 0644 "${UNPACKDIR}/odoo.service" \
        "${D}${systemd_system_unitdir}/odoo.service"
    install -m 0644 "${UNPACKDIR}/odoo-conda-unpack.service" \
        "${D}${systemd_system_unitdir}/odoo-conda-unpack.service"
    install -m 0644 "${UNPACKDIR}/postgresql-odoo-setup.service" \
        "${D}${systemd_system_unitdir}/postgresql-odoo-setup.service"

    # Remove Python build/devel config artifacts not needed at runtime.
    # They may contain very long shebangs inside the relocated conda prefix,
    # tripping do_package_qa [shebang-size].
    rm -rf "${D}/opt/odoo-env/lib/python3.12/config-3.12-"*
    rm -f "${D}/opt/odoo-env/bin/python3-config" \
          "${D}/opt/odoo-env/bin/python3.12-config"

    # Ensure deterministic root ownership in ${D}; prevents host contamination
    # (e.g. uid/gid 1000) detected by sstate/do_package checks.
    chown -R root:root "${D}/opt/odoo" "${D}/opt/odoo-env" "${D}/home/odoo" \
        "${D}${sysconfdir}/odoo" "${D}${localstatedir}/lib/odoo/log"
}

pkg_postinst:${PN}() {
    chown -R odoo:odoo /opt/odoo
    chown -R odoo:odoo /opt/odoo-env
    chown -R odoo:odoo /home/odoo
    chown root:odoo /etc/odoo/odoo.conf
    chown -R odoo:odoo /var/lib/odoo/log
}

FILES:${PN} = " \
    /opt/odoo \
    /opt/odoo-env \
    /home/odoo \
    ${sysconfdir}/odoo \
    ${localstatedir}/lib/odoo/log \
    ${libexecdir}/postgresql-odoo-setup.sh \
    ${systemd_system_unitdir}/odoo.service \
    ${systemd_system_unitdir}/odoo-conda-unpack.service \
    ${systemd_system_unitdir}/postgresql-odoo-setup.service \
"

# conda-forge ships stripped binaries; conda-pack records the original build
# prefix; some conda packages include .so and .a files outside the usual paths.
# file-rdeps: /opt/odoo-env bundles private wheel-shipped DSOs with hashed SONAMEs
# (e.g. libssl-*.so.1.1, libkrb5-*.so.*). They are intentionally self-contained
# and not resolvable via Yocto package providers.
INSANE_SKIP:${PN} += "already-stripped buildpaths dev-so staticdev file-rdeps"
