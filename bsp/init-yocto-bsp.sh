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
echo "1. source bitbake-builds/poky-master/build/init-build-env"
echo "2. bitbake-config-build disable-fragment distro/poky"
echo "3. bitbake-layers add-layer meta-odoo-pos"
echo "4. bitbake-layers show-layers"
echo "5. export DISTRO=odoo-pos-system"
echo "6. bitbake odoo-pos-image"
