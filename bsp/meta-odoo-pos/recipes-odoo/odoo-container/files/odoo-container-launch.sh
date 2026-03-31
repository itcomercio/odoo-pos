#!/bin/sh
set -eu

if [ -f /etc/default/odoo-container ]; then
    # shellcheck disable=SC1091
    . /etc/default/odoo-container
fi

: "${ODOO_CONTAINER_IMAGE:=localhost/odoo-pos:19.0}"
: "${ODOO_CONTAINER_NAME:=odoo}"

mkdir -p /var/lib/odoo/log

# Keep host PostgreSQL and container in the same network namespace to simplify
# DB connectivity (127.0.0.1:5432 from inside container == host PostgreSQL).
exec podman run --rm --replace \
    --name "${ODOO_CONTAINER_NAME}" \
    --network host \
    -v /var/lib/odoo:/var/lib/odoo:Z \
    -v /etc/odoo/odoo.conf:/etc/odoo/odoo.conf:ro,Z \
    -e PGHOST=127.0.0.1 \
    -e PGPORT=5432 \
    -e PGUSER=odoo \
    -e PGPASSWORD=odoo \
    -e DB_NAME=odoo \
    -e HTTP_PORT=8069 \
    -e ODOO_URL=http://127.0.0.1:8069 \
    -e ODOO_CONFIG=/etc/odoo/odoo.conf \
    -e ODOO_DATA_DIR=/var/lib/odoo \
    -e ADMIN_USERNAME=odoo@example.com \
    -e ADMIN_PASSWORD=adm \
    -e MASTER_PASSWORD=miadminpasswordodoo \
    "${ODOO_CONTAINER_IMAGE}"

