#!/bin/sh
set -eu

PGDATA="/var/lib/postgresql/data"

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

exec su -s /bin/sh postgres -c "/usr/bin/initdb -D '${PGDATA}' --encoding=UTF8 --locale=C"

