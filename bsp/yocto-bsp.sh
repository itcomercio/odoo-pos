#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE_DIR="${SCRIPT_DIR}"
ORIGINAL_DIR=$(pwd)
META_LAYER_DIR="${WORKSPACE_DIR}/meta-odoo-pos"
BUILD_ENV_SCRIPT="${WORKSPACE_DIR}/bitbake-builds/poky-master/build/init-build-env"
TARGET_DISTRO='DISTRO = "odoo-pos-system"'
BUILD_TARGET="odoo-pos-image"
RUN_BUILD=0
MODE_SELECTED=""

cleanup() {
    cd "${ORIGINAL_DIR}" || true
}

info() {
    echo "[INFO] $*"
}

usage() {
    cat <<'EOF'
Uso: ./yocto-bsp.sh --no-build
   o: ./yocto-bsp.sh --build

Opciones:
  --no-build   Prepara el entorno Yocto y lo deja listo para ejecutar manualmente `bitbake odoo-pos-image`
  --build      Prepara el entorno Yocto y ejecuta `bitbake odoo-pos-image`
  -h, --help   Muestra esta ayuda
EOF
}

if [ "$#" -eq 0 ]; then
    usage
    exit 0
fi

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-build)
            if [ -n "${MODE_SELECTED}" ] && [ "${MODE_SELECTED}" != "no-build" ]; then
                echo "[ERROR] No puedes combinar --no-build y --build" >&2
                usage >&2
                exit 1
            fi
            MODE_SELECTED="no-build"
            ;;
        --build)
            if [ -n "${MODE_SELECTED}" ] && [ "${MODE_SELECTED}" != "build" ]; then
                echo "[ERROR] No puedes combinar --no-build y --build" >&2
                usage >&2
                exit 1
            fi
            MODE_SELECTED="build"
            RUN_BUILD=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Opcion no soportada: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

trap cleanup EXIT

cd "${WORKSPACE_DIR}"

if [ -d "bitbake" ]; then
    info "bitbake ya existe en ${WORKSPACE_DIR}/bitbake; se omite clone"
else
    info "Clonando bitbake"
    git clone https://git.openembedded.org/bitbake
fi

info "Inicializando entorno Yocto base"
./bitbake/bin/bitbake-setup init --non-interactive poky-master poky-with-sstate distro/poky machine/qemux86-64

info "Eliminando clon temporal de bitbake"
rm -rf bitbake

if [ ! -f "${BUILD_ENV_SCRIPT}" ]; then
    echo "[ERROR] No existe ${BUILD_ENV_SCRIPT}" >&2
    exit 1
fi

info "Cargando entorno de build Yocto"
# init-build-env/oe-init-build-env no es compatible con nounset heredado.
set +u
# shellcheck source=/dev/null
source "${BUILD_ENV_SCRIPT}"
set -u

info "Desactivando fragmento builtin distro/poky"
if ! bitbake-config-build disable-fragment distro/poky; then
    echo "[WARN] No se pudo desactivar distro/poky o ya estaba desactivado; se continua" >&2
fi

info "Comprobando si la capa meta-odoo-pos ya esta registrada"
if bitbake-layers show-layers | awk 'NR > 2 {print $1}' | grep -qx 'odoo-pos'; then
    info "La capa meta-odoo-pos ya esta anadida"
else
    info "Anadiendo capa ${META_LAYER_DIR}"
    bitbake-layers add-layer "${META_LAYER_DIR}"
fi

info "Mostrando capas activas"
bitbake-layers show-layers

BUILD_DIR="${BUILDDIR:-$(pwd)}"
LOCAL_CONF="${BUILD_DIR}/conf/local.conf"
if [ ! -f "${LOCAL_CONF}" ]; then
    echo "[ERROR] No existe ${LOCAL_CONF}" >&2
    exit 1
fi

info "Configurando DISTRO=odoo-pos-system en ${LOCAL_CONF}"
if grep -Eq '^[[:space:]]*DISTRO[[:space:]]*=' "${LOCAL_CONF}"; then
    sed -i -E 's|^[[:space:]]*DISTRO[[:space:]]*=.*$|DISTRO = "odoo-pos-system"|' "${LOCAL_CONF}"
else
    printf '\n%s\n' "${TARGET_DISTRO}" >> "${LOCAL_CONF}"
fi

if [ "${RUN_BUILD}" -eq 1 ]; then
    info "Lanzando build de ${BUILD_TARGET}"
    bitbake "${BUILD_TARGET}"
else
    info "Entorno Yocto preparado"
    info "Build dir: ${BUILD_DIR}"
    info "Config: ${LOCAL_CONF}"
    info "Para compilar manualmente ejecuta:"
    info "cd ${BUILD_DIR} && bitbake ${BUILD_TARGET}"
fi

