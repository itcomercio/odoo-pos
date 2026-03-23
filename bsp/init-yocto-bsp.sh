#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE_DIR="${SCRIPT_DIR}/yocto-project"

mkdir -p "${WORKSPACE_DIR}"
cd "${WORKSPACE_DIR}"

if [ -d "bitbake" ]; then
    echo "[INFO] bitbake ya existe en ${WORKSPACE_DIR}/bitbake; se omite clone"
else
    git clone https://git.openembedded.org/bitbake
    rm -rf bitbake/.git
fi

cd bitbake
bitbake-setup init --non-interactive poky-master poky-with-sstate distro/poky machine/qemux86-64

