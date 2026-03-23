#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE_DIR="${SCRIPT_DIR}"

cd "${WORKSPACE_DIR}"

if [ -d "bitbake" ]; then
    echo "[INFO] bitbake ya existe en ${WORKSPACE_DIR}/bitbake; se omite clone"
else
    git clone https://git.openembedded.org/bitbake
fi

./bitbake/bin/bitbake-setup init --non-interactive poky-master poky-with-sstate distro/poky machine/qemux86-64

rm -rf bitbake

# Add custom layers to:
# bitbake-builds/poky-master/build/conf/bblayers.conf
bitbake-layers add-layer meta-odoo-pos
bitbake-layers show-layers

echo "source bitbake-builds/poky-master/build/init-build-env"
# core-image-weston: A very basic Wayland image with a terminal.
# This image provides the Wayland protocol libraries and the
# reference Weston compositor.
echo "bitbake core-image-weston"
