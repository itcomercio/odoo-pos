#!/bin/sh
set -eu

PGDATA="/var/lib/postgresql/data"
TUNING_SRC="/etc/postgresql/odoo-tuning.conf"

if [ -f "${PGDATA}/PG_VERSION" ]; then
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "postgresql-initdb.sh must run as root" >&2
    exit 1
fi

mkdir -p "${PGDATA}"
chmod 0700 "${PGDATA}"
chown -R postgres:postgres /var/lib/postgresql

# Run initdb (without exec so we can add steps afterwards)
su -s /bin/sh postgres -c "/usr/bin/initdb -D '${PGDATA}' --encoding=UTF8 --locale=C"

# ------------------------------------------------------------------
# Apply Odoo-recommended PostgreSQL tuning
# Install the tuning snippet into PGDATA/conf.d/ and activate it via
# include_dir in postgresql.conf (PostgreSQL 9.3+).
# ------------------------------------------------------------------
if [ -f "${TUNING_SRC}" ]; then
    CONFDIR="${PGDATA}/conf.d"
    mkdir -p "${CONFDIR}"
    cp "${TUNING_SRC}" "${CONFDIR}/odoo-tuning.conf"
    chown -R postgres:postgres "${CONFDIR}"
    chmod 0700 "${CONFDIR}"
    chmod 0600 "${CONFDIR}/odoo-tuning.conf"

    # Append include_dir directive only if not already present
    if ! grep -q "^include_dir" "${PGDATA}/postgresql.conf"; then
        echo "" >> "${PGDATA}/postgresql.conf"
        echo "# Odoo POS tuning — loaded from conf.d/" >> "${PGDATA}/postgresql.conf"
        echo "include_dir = 'conf.d'" >> "${PGDATA}/postgresql.conf"
    fi
    echo "PostgreSQL Odoo tuning applied from ${TUNING_SRC}"
else
    echo "WARNING: tuning file ${TUNING_SRC} not found, skipping tuning." >&2
fi

