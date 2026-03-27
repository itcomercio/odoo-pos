#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE_DIR="${SCRIPT_DIR}"
ORIGINAL_DIR=$(pwd)
META_LAYER_DIR="${WORKSPACE_DIR}/meta-odoo-pos"
BITBAKE_BUILDS_DIR="${WORKSPACE_DIR}/bitbake-builds"
META_OPENEMBEDDED_REPO_DIR="${BITBAKE_BUILDS_DIR}/meta-openembedded"
META_OE_LAYER_DIR="${META_OPENEMBEDDED_REPO_DIR}/meta-oe"
META_BROWSER_REPO_DIR="${BITBAKE_BUILDS_DIR}/meta-browser"
META_CHROMIUM_LAYER_DIR="${META_BROWSER_REPO_DIR}/meta-chromium"
BUILD_ENV_SCRIPT="${WORKSPACE_DIR}/bitbake-builds/poky-master/build/init-build-env"
TARGET_DISTRO='DISTRO = "odoo-pos-system"'
BUILD_TARGET="odoo-pos-image"
RUN_BUILD=0
MODE_SELECTED=""
BOOTSTRAPPED_NOW=0

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

if [ -d "${BITBAKE_BUILDS_DIR}" ]; then
    info "bitbake-builds ya existe; se omite inicializacion base"
else
    if [ -d "bitbake" ]; then
        info "bitbake ya existe en ${WORKSPACE_DIR}/bitbake; se omite clone"
    else
        info "Clonando bitbake"
        git clone https://git.openembedded.org/bitbake
    fi

    info "Inicializando entorno Yocto base"
    ./bitbake/bin/bitbake-setup init --non-interactive poky-master poky-with-sstate distro/poky machine/genericx86-64

    info "Eliminando clon temporal de bitbake"
    rm -rf bitbake
    BOOTSTRAPPED_NOW=1
fi

if [ ! -f "${BUILD_ENV_SCRIPT}" ]; then
    echo "[ERROR] No existe ${BUILD_ENV_SCRIPT}" >&2
    exit 1
fi

if [ -d "${META_BROWSER_REPO_DIR}" ]; then
    info "meta-browser ya existe en ${META_BROWSER_REPO_DIR}; se omite clone"
else
    info "Clonando meta-browser"
    git clone https://github.com/OSSystems/meta-browser/ "${META_BROWSER_REPO_DIR}"
fi

if [ -d "${META_OPENEMBEDDED_REPO_DIR}" ]; then
    info "meta-openembedded ya existe en ${META_OPENEMBEDDED_REPO_DIR}; se omite clone"
else
    info "Clonando meta-openembedded"
    git clone https://github.com/openembedded/meta-openembedded.git "${META_OPENEMBEDDED_REPO_DIR}"
fi

info "Cargando entorno de build Yocto"
# init-build-env/oe-init-build-env no es compatible con nounset heredado.
set +u
# shellcheck source=/dev/null
source "${BUILD_ENV_SCRIPT}"
set -u

if [ "${BOOTSTRAPPED_NOW}" -eq 1 ] || [ "${RUN_BUILD}" -eq 1 ]; then
    info "Desactivando fragmento builtin distro/poky"
    if ! bitbake-config-build disable-fragment distro/poky; then
        echo "[WARN] No se pudo desactivar distro/poky o ya estaba desactivado; se continua" >&2
    fi
else
    info "Se omite ajuste de fragmentos (modo idempotente --no-build con bitbake-builds existente)"
fi

info "Comprobando si la capa meta-odoo-pos ya esta registrada"
if bitbake-layers show-layers | awk 'NR > 2 {print $1}' | grep -qx 'odoo-pos'; then
    info "La capa meta-odoo-pos ya esta anadida"
else
    info "Anadiendo capa ${META_LAYER_DIR}"
    bitbake-layers add-layer "${META_LAYER_DIR}"
fi

if [ ! -d "${META_CHROMIUM_LAYER_DIR}" ]; then
    echo "[ERROR] No existe la capa ${META_CHROMIUM_LAYER_DIR}" >&2
    exit 1
fi

if [ ! -d "${META_OE_LAYER_DIR}" ]; then
    echo "[ERROR] No existe la capa ${META_OE_LAYER_DIR}" >&2
    exit 1
fi

info "Comprobando si la capa openembedded-layer (meta-oe) ya esta registrada"
if bitbake-layers show-layers | awk 'NR > 2 {print $1}' | grep -qx 'openembedded-layer'; then
    info "La capa openembedded-layer ya esta anadida"
else
    info "Anadiendo capa ${META_OE_LAYER_DIR}"
    bitbake-layers add-layer "${META_OE_LAYER_DIR}"
fi

info "Comprobando si la capa meta-chromium ya esta registrada"
if bitbake-layers show-layers | awk 'NR > 2 {print $1}' | grep -qx 'meta-chromium'; then
    info "La capa meta-chromium ya esta anadida"
else
    info "Anadiendo capa ${META_CHROMIUM_LAYER_DIR}"
    bitbake-layers add-layer "${META_CHROMIUM_LAYER_DIR}"
fi

info "Mostrando capas activas"
bitbake-layers show-layers

BUILD_DIR="${BUILDDIR:-$(pwd)}"
LOCAL_CONF="${BUILD_DIR}/conf/local.conf"
if [ ! -f "${LOCAL_CONF}" ]; then
    echo "[ERROR] No existe ${LOCAL_CONF}" >&2
    exit 1
fi

if [ "${BOOTSTRAPPED_NOW}" -eq 1 ] || [ "${RUN_BUILD}" -eq 1 ]; then
    info "Configurando DISTRO=odoo-pos-system en ${LOCAL_CONF}"
    if grep -Eq '^[[:space:]]*DISTRO[[:space:]]*=' "${LOCAL_CONF}"; then
        sed -i -E 's|^[[:space:]]*DISTRO[[:space:]]*=.*$|DISTRO = "odoo-pos-system"|' "${LOCAL_CONF}"
    else
        printf '\n%s\n' "${TARGET_DISTRO}" >> "${LOCAL_CONF}"
    fi
else
    info "Se omite ajuste de DISTRO en local.conf (modo idempotente --no-build con bitbake-builds existente)"
fi


if [ "${RUN_BUILD}" -eq 1 ]; then
    info "Lanzando build de ${BUILD_TARGET}"
    bitbake "${BUILD_TARGET}"
else
    info "Entorno Yocto preparado"
    info "Build dir: ${BUILD_DIR}"
    info "Config: ${LOCAL_CONF}"
    info "Para compilar manualmente ejecuta:"
    info "source bitbake-builds/poky-master/build/init-build-env && bitbake ${BUILD_TARGET}"
fi

