#!/bin/sh
set -eu

if [ -f /etc/default/odoo-container ]; then
    # shellcheck disable=SC1091
    . /etc/default/odoo-container
fi

: "${ODOO_CONTAINER_IMAGE:=localhost/odoo-pos:19.0}"

CONTAINER_TAR="/var/lib/odoo/odoo-container.tar"
IMPORT_MARKER="/var/lib/odoo/.odoo-container-imported"

if [ -f "${IMPORT_MARKER}" ]; then
    echo "Odoo container image already imported, skipping."
    exit 0
fi

if [ ! -f "${CONTAINER_TAR}" ]; then
    echo "Missing container tarball: ${CONTAINER_TAR}" >&2
    exit 1
fi

if podman image exists "${ODOO_CONTAINER_IMAGE}"; then
    echo "Odoo container image ${ODOO_CONTAINER_IMAGE} already present, writing marker."
    touch "${IMPORT_MARKER}"
    exit 0
fi

echo "Importing OCI image from ${CONTAINER_TAR}"
podman load -i "${CONTAINER_TAR}"

touch "${IMPORT_MARKER}"

# Free disk space — the tar is no longer needed once loaded into Podman storage.
echo "Removing ${CONTAINER_TAR} to reclaim disk space"
rm -f "${CONTAINER_TAR}"

