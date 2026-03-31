#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE_DIR="${SCRIPT_DIR}"
ORIGINAL_DIR=$(pwd)
META_LAYER_DIR="${WORKSPACE_DIR}/meta-odoo-pos"
BITBAKE_BUILDS_DIR="${WORKSPACE_DIR}/bitbake-builds"
META_OPENEMBEDDED_REPO_DIR="${BITBAKE_BUILDS_DIR}/meta-openembedded"
META_OE_LAYER_DIR="${META_OPENEMBEDDED_REPO_DIR}/meta-oe"
META_PYTHON_LAYER_DIR="${META_OPENEMBEDDED_REPO_DIR}/meta-python"
META_NETWORKING_LAYER_DIR="${META_OPENEMBEDDED_REPO_DIR}/meta-networking"
META_FILESYSTEMS_LAYER_DIR="${META_OPENEMBEDDED_REPO_DIR}/meta-filesystems"
META_BROWSER_REPO_DIR="${BITBAKE_BUILDS_DIR}/meta-browser"
META_CHROMIUM_LAYER_DIR="${META_BROWSER_REPO_DIR}/meta-chromium"
META_VIRTUALIZATION_REPO_DIR="${BITBAKE_BUILDS_DIR}/meta-virtualization"
META_VIRTUALIZATION_LAYER_DIR="${META_VIRTUALIZATION_REPO_DIR}"
BUILD_ENV_SCRIPT="${WORKSPACE_DIR}/bitbake-builds/poky-master/build/init-build-env"
TARGET_DISTRO='DISTRO = "odoo-pos-system"'
BUILD_TARGET="odoo-pos-image"
ODOO_CONTAINER_CONTEXT_ROOT_DIR="${META_LAYER_DIR}/containers/odoo"
ODOO_CONTAINER_CONTEXT_DIR=""
ODOO_CONTAINER_RECIPE_FILES_DIR="${META_LAYER_DIR}/recipes-odoo/odoo-container/files"
ODOO_CONTAINER_OUTPUT_TAR="${ODOO_CONTAINER_RECIPE_FILES_DIR}/odoo-image.tar"
ODOO_CONTAINER_IMAGE_TAG="localhost/odoo-pos:19.0"
ODOO_CONTAINER_ENGINE=""
RUN_BUILD=0
MODE_SELECTED=""
BOOTSTRAPPED_NOW=0
BUILD_ODOO_CONTAINER_IMAGE=0

cleanup() {
    cd "${ORIGINAL_DIR}" || true
}

info() {
    echo "[INFO] $*"
}

ensure_layer() {
    local layer_name="$1"
    local layer_dir="$2"

    if [ ! -d "${layer_dir}/conf" ]; then
        echo "[ERROR] No existe la capa ${layer_dir}" >&2
        exit 1
    fi

    info "Comprobando si la capa ${layer_name} ya esta registrada"
    if bitbake-layers show-layers | awk 'NR > 2 {print $1}' | grep -qx "${layer_name}"; then
        info "La capa ${layer_name} ya esta anadida"
    else
        info "Anadiendo capa ${layer_dir}"
        bitbake-layers add-layer "${layer_dir}"
    fi
}

usage() {
    cat <<'EOF'
Uso:
  ./yocto-bsp.sh --no-build
  ./yocto-bsp.sh --build
  ./yocto-bsp.sh --build-odoo-container-image [--no-build|--build]

Opciones:
  --no-build                    Prepara el entorno Yocto y lo deja listo para ejecutar manualmente `bitbake odoo-pos-image`
  --build                       Prepara el entorno Yocto y ejecuta `bitbake odoo-pos-image`
  --build-odoo-container-image  Construye la imagen OCI personalizada de Odoo desde `meta-odoo-pos/containers/odoo/<version>/` (autodetectado),
                                y exporta `odoo-image.tar` para incluirlo en el medio de instalacion
  --container-context <dir>     Contexto OCI a usar (si se omite, autodetecta Dockerfile en `meta-odoo-pos/containers/odoo`)
  --container-engine <engine>   Fuerza el motor del host para construir la imagen OCI (`podman` o `docker`)
  --container-tag <image>       Tag de la imagen OCI a construir (por defecto: localhost/odoo-pos:19.0)
  --container-output <tar>      Ruta de salida del tar OCI (por defecto: meta-odoo-pos/recipes-odoo/odoo-container/files/odoo-image.tar)
  -h, --help                    Muestra esta ayuda

Flujos recomendados:
  1. Construir solo la imagen OCI personalizada de Odoo:
       ./yocto-bsp.sh --build-odoo-container-image

  2. Construir la imagen OCI y dejar Yocto preparado sin lanzar BitBake:
       ./yocto-bsp.sh --build-odoo-container-image --no-build

  3. Construir la imagen OCI y lanzar toda la build Yocto:
       ./yocto-bsp.sh --build-odoo-container-image --build

  4. Si ya existe `odoo-image.tar`, preparar Yocto sin reconstruir el contenedor:
       ./yocto-bsp.sh --no-build

  5. Si ya existe `odoo-image.tar`, lanzar directamente la build Yocto:
       ./yocto-bsp.sh --build
EOF
}


resolve_odoo_container_context_dir() {
    if [ -n "${ODOO_CONTAINER_CONTEXT_DIR}" ]; then
        return 0
    fi

    if [ ! -d "${ODOO_CONTAINER_CONTEXT_ROOT_DIR}" ]; then
        echo "[ERROR] No existe el directorio base de contextos OCI ${ODOO_CONTAINER_CONTEXT_ROOT_DIR}" >&2
        exit 1
    fi

    if [ -f "${ODOO_CONTAINER_CONTEXT_ROOT_DIR}/Dockerfile" ]; then
        ODOO_CONTAINER_CONTEXT_DIR="${ODOO_CONTAINER_CONTEXT_ROOT_DIR}"
        return 0
    fi

    mapfile -t docker_context_candidates < <(
        find "${ODOO_CONTAINER_CONTEXT_ROOT_DIR}" -mindepth 2 -maxdepth 2 -type f -name Dockerfile -printf '%h\n' | sort -u
    )

    if [ "${#docker_context_candidates[@]}" -eq 1 ]; then
        ODOO_CONTAINER_CONTEXT_DIR="${docker_context_candidates[0]}"
        return 0
    fi

    if [ "${#docker_context_candidates[@]}" -eq 0 ]; then
        echo "[ERROR] No se encontro ningun Dockerfile en ${ODOO_CONTAINER_CONTEXT_ROOT_DIR}" >&2
        echo "[ERROR] Usa --container-context <dir> para especificar el contexto manualmente" >&2
        exit 1
    fi

    echo "[ERROR] Se encontraron multiples contextos OCI con Dockerfile en ${ODOO_CONTAINER_CONTEXT_ROOT_DIR}:" >&2
    printf '  - %s\n' "${docker_context_candidates[@]}" >&2
    echo "[ERROR] Usa --container-context <dir> para seleccionar uno" >&2
    exit 1
}

build_odoo_container_image() {
    local engine="${ODOO_CONTAINER_ENGINE}"

    resolve_odoo_container_context_dir

    if [ -z "${engine}" ]; then
        if command -v podman >/dev/null 2>&1; then
            engine="podman"
        elif command -v docker >/dev/null 2>&1; then
            engine="docker"
        else
            echo "[ERROR] No se encontro podman ni docker en el host" >&2
            exit 1
        fi
    fi

    if [ ! -d "${ODOO_CONTAINER_CONTEXT_DIR}" ]; then
        echo "[ERROR] No existe el contexto OCI ${ODOO_CONTAINER_CONTEXT_DIR}" >&2
        exit 1
    fi

    if [ ! -f "${ODOO_CONTAINER_CONTEXT_DIR}/Dockerfile" ]; then
        echo "[ERROR] No existe Dockerfile en el contexto OCI ${ODOO_CONTAINER_CONTEXT_DIR}" >&2
        exit 1
    fi

    mkdir -p "$(dirname "${ODOO_CONTAINER_OUTPUT_TAR}")"

    info "Construyendo imagen OCI personalizada de Odoo"
    info "Engine: ${engine}"
    info "Context: ${ODOO_CONTAINER_CONTEXT_DIR}"
    info "Tag: ${ODOO_CONTAINER_IMAGE_TAG}"
    info "Output tar: ${ODOO_CONTAINER_OUTPUT_TAR}"

    "${engine}" build -t "${ODOO_CONTAINER_IMAGE_TAG}" "${ODOO_CONTAINER_CONTEXT_DIR}"
    rm -f "${ODOO_CONTAINER_OUTPUT_TAR}"
    "${engine}" save -o "${ODOO_CONTAINER_OUTPUT_TAR}" "${ODOO_CONTAINER_IMAGE_TAG}"

    info "Imagen OCI exportada correctamente"
    ls -lh "${ODOO_CONTAINER_OUTPUT_TAR}"
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
        --build-odoo-container-image)
            BUILD_ODOO_CONTAINER_IMAGE=1
            ;;
        --container-context)
            ODOO_CONTAINER_CONTEXT_DIR="$2"
            shift
            ;;
        --container-engine)
            ODOO_CONTAINER_ENGINE="$2"
            shift
            ;;
        --container-tag)
            ODOO_CONTAINER_IMAGE_TAG="$2"
            shift
            ;;
        --container-output)
            ODOO_CONTAINER_OUTPUT_TAR="$2"
            shift
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

if [ "${BUILD_ODOO_CONTAINER_IMAGE}" -eq 1 ]; then
    build_odoo_container_image
    if [ -z "${MODE_SELECTED}" ]; then
        info "Imagen OCI preparada; no se ha solicitado ninguna accion Yocto adicional"
        exit 0
    fi
elif [ "${RUN_BUILD}" -eq 1 ] && [ ! -f "${ODOO_CONTAINER_OUTPUT_TAR}" ]; then
    echo "[WARN] No existe ${ODOO_CONTAINER_OUTPUT_TAR}" >&2
    echo "[WARN] La build Yocto puede continuar, pero la ISO de instalacion requerira ese tar" >&2
fi

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

if [ -d "${META_VIRTUALIZATION_REPO_DIR}" ]; then
    info "meta-virtualization ya existe en ${META_VIRTUALIZATION_REPO_DIR}; se omite clone"
else
    info "Clonando meta-virtualization"
    git clone https://git.yoctoproject.org/meta-virtualization "${META_VIRTUALIZATION_REPO_DIR}"
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

ensure_layer "odoo-pos" "${META_LAYER_DIR}"

if [ ! -d "${META_CHROMIUM_LAYER_DIR}" ]; then
    echo "[ERROR] No existe la capa ${META_CHROMIUM_LAYER_DIR}" >&2
    exit 1
fi

ensure_layer "openembedded-layer" "${META_OE_LAYER_DIR}"
ensure_layer "meta-python" "${META_PYTHON_LAYER_DIR}"
ensure_layer "networking-layer" "${META_NETWORKING_LAYER_DIR}"
ensure_layer "filesystems-layer" "${META_FILESYSTEMS_LAYER_DIR}"
ensure_layer "meta-chromium" "${META_CHROMIUM_LAYER_DIR}"
ensure_layer "virtualization-layer" "${META_VIRTUALIZATION_LAYER_DIR}"

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

