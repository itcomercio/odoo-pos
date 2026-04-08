#!/bin/sh
set -eu

if [ -f /etc/default/odoo-container ]; then
    # shellcheck disable=SC1091
    . /etc/default/odoo-container
fi

: "${ODOO_CONTAINER_IMAGE:=localhost/odoo-pos:19.0}"
: "${ODOO_CONTAINER_NAME:=odoo}"
: "${ODOO_LIMIT_TIME_REAL:=900}"
: "${ODOO_LIMIT_MEMORY_SOFT:=2147483648}"
: "${ODOO_LIMIT_MEMORY_HARD:=2684354560}"

# Ensure all Odoo data directories exist on the host volume.
# Always enforce write permissions because the directory may already exist
# from previous installs with restrictive ownership/mode on the host.
for d in /var/lib/odoo /var/lib/odoo/log /var/lib/odoo/sessions /var/lib/odoo/filestore; do
    mkdir -p "$d"
    chmod 0777 "$d"
done

# Pre-flight: verify the OCI image was imported successfully.
if ! podman image exists "${ODOO_CONTAINER_IMAGE}"; then
    echo "ERROR: Container image ${ODOO_CONTAINER_IMAGE} not found." >&2
    echo "Check that odoo-container-import.service completed successfully." >&2
    echo "Available images:" >&2
    podman images --format "{{.Repository}}:{{.Tag}}" >&2
    exit 1
fi

echo "Starting Odoo container '${ODOO_CONTAINER_NAME}' from image '${ODOO_CONTAINER_IMAGE}'"

if podman container exists "${ODOO_CONTAINER_NAME}"; then
    echo "Reusing existing container '${ODOO_CONTAINER_NAME}'"
    exec podman start -a "${ODOO_CONTAINER_NAME}"
fi

# Keep host PostgreSQL and container in the same network namespace to simplify
# DB connectivity (127.0.0.1:5432 from inside container == host PostgreSQL).
exec podman run \
    --name "${ODOO_CONTAINER_NAME}" \
    --pull=never \
    --network host \
    -v /var/lib/odoo:/var/lib/odoo:Z \
    -v /etc/odoo/odoo.conf:/etc/odoo/odoo.conf:ro,Z \
    -e PGHOST=127.0.0.1 \
    -e PGPORT=5432 \
    -e PGUSER=odoo \
    -e PGPASSWORD=odoo \
    -e DB_NAME=odoo \
    -e HTTP_PORT=8069 \
    -e ODOO_LIMIT_TIME_REAL="${ODOO_LIMIT_TIME_REAL}" \
    -e ODOO_LIMIT_MEMORY_SOFT="${ODOO_LIMIT_MEMORY_SOFT}" \
    -e ODOO_LIMIT_MEMORY_HARD="${ODOO_LIMIT_MEMORY_HARD}" \
    -e ODOO_URL=http://127.0.0.1:8069 \
    -e ODOO_CONFIG=/etc/odoo/odoo.conf \
    -e ODOO_DATA_DIR=/var/lib/odoo \
    -e ADMIN_USERNAME=odoo@example.com \
    -e ADMIN_PASSWORD=adm \
    -e MASTER_PASSWORD=miadminpasswordodoo \
    "${ODOO_CONTAINER_IMAGE}"
