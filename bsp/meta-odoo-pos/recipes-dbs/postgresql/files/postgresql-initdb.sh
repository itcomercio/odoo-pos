#!/bin/sh
set -eu

PGDATA="/var/lib/postgresql/data"

if [ -f "${PGDATA}/PG_VERSION" ]; then
    exit 0
fi

install -d -m 0700 "${PGDATA}"
chown -R postgres:postgres /var/lib/postgresql

exec /usr/bin/initdb -D "${PGDATA}" --encoding=UTF8 --locale=C

