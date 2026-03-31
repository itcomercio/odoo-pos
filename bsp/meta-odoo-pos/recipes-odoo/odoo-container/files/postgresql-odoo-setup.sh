#!/bin/bash
set -euo pipefail

MARKER="/var/lib/postgresql/odoo-db-setup-done"

if [ -f "${MARKER}" ]; then
    echo "PostgreSQL Odoo setup already completed, skipping."
    exit 0
fi

echo "Waiting for PostgreSQL to accept connections..."
for i in $(seq 1 30); do
    if su -s /bin/sh postgres -c "/usr/bin/pg_isready -q"; then
        echo "PostgreSQL is ready."
        break
    fi
    echo "  attempt ${i}/30 - sleeping 2 s..."
    sleep 2
done

if ! su -s /bin/sh postgres -c "/usr/bin/pg_isready -q"; then
    echo "ERROR: PostgreSQL did not become ready in time." >&2
    exit 1
fi

echo "Creating PostgreSQL role 'odoo'..."
su -s /bin/sh postgres -c "psql -tc \
    \"SELECT 1 FROM pg_roles WHERE rolname='odoo'\" \
    | grep -q 1 || \
    psql -c \"CREATE ROLE odoo WITH LOGIN PASSWORD 'odoo';\""

echo "Creating PostgreSQL database 'odoo'..."
su -s /bin/sh postgres -c "psql -tc \
    \"SELECT 1 FROM pg_database WHERE datname='odoo'\" \
    | grep -q 1 || \
    psql -c \"CREATE DATABASE odoo OWNER odoo;\""

echo "PostgreSQL Odoo setup complete."
touch "${MARKER}"

