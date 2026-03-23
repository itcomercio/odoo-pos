#!/usr/bin/env bash
#
# Creates a bootable ISO image using Limine and makes it bootable.
#
# Nota: Para inspescionar la imagen ISO final usar este comando
# isoinfo -f -R -i comodoo.iso | grep -i limine.conf
#
# Nota: Para inspeccionar la imagen initrd final usar este comando
# cpio -i -t < CD/boot/initrd.img | head -20
# Aunque es más comodo este otro:
# lsinitrd CD/boot/initrd.img

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/include/functions.env"

OUTPUT_ISO="comodoo.iso"
ISO_LABEL="COMODOO_INSTALL"
LIMINE_DIR="${SCRIPT_DIR}/limine"
YOCTO_DIR="${SCRIPT_DIR}/yocto"
LIMINE_DEPLOY="${LIMINE_DIR}/limine-deploy"
BSP_OUTPUT_NAME="beetlepos-image-beetlepos.bsp"

usage() {
    cat <<'EOF'
Uso: ./_03-mk-cdrom.sh <directorio_cd>

Prepara el arbol del CD y genera la ISO arrancable con Limine.

Ejemplo:
    ./_03-mk-cdrom.sh "${PWD}/CD"
EOF
    exit 1
}

find_single_file() {
    local description="$1"
    shift

    local matches=()
    local pattern
    local match

    for pattern in "$@"; do
        while IFS= read -r match; do
            matches+=("$match")
        done < <(compgen -G "$pattern" || true)
    done

    if [ "${#matches[@]}" -eq 0 ]; then
        echo_note "ERROR" "No se ha encontrado ${description}." >&2
        return 1
    fi

    if [ "${#matches[@]}" -gt 1 ]; then
        echo_note "WARNING" "Se han encontrado varios candidatos para ${description}; se usara el primero." >&2
    fi

    printf '%s\n' "${matches[0]}"
}

copy_required_file() {
    local src="$1"
    local dest="$2"
    local description="$3"

    if [ ! -f "$src" ]; then
        echo_note "ERROR" "Falta ${description}: ${src}"
        exit 1
    fi

    cp -f "$src" "$dest"
}

write_limine_config() {
    local limine_conf="$1"

    cat > "$limine_conf" <<'EOF'
timeout: 5
verbose: yes
interface_help_colour: 3

/Comodoo Installer
    protocol: linux
    path: boot():/boot/vmlinuz
    module_path: boot():/boot/initrd.img
EOF
}

[ -z "${1:-}" ] && usage

CD_TREE_DIR="$1"
CD_BOOT_DIR="${CD_TREE_DIR}/boot"
CD_LIMINE_DIR="${CD_BOOT_DIR}/limine"
CD_EFI_BOOT_DIR="${CD_TREE_DIR}/EFI/BOOT"
CD_BSP_DIR="${CD_TREE_DIR}/bsp"
CD_IMAGES_DIR="${CD_TREE_DIR}/images"
INITRD_IMAGE="${CD_BOOT_DIR}/initrd.img"
KERNEL_DEST="${CD_BOOT_DIR}/vmlinuz"
BSP_DEST="${CD_BSP_DIR}/${BSP_OUTPUT_NAME}"
LIMINE_CONF="${CD_LIMINE_DIR}/limine.conf"
ROOT_LIMINE_CONF="${CD_TREE_DIR}/limine.conf"

KERNEL_SOURCE=$(find_single_file "la imagen de kernel Yocto (bzImage*)" "${YOCTO_DIR}/bzImage*") || exit 1
BSP_SOURCE=$(find_single_file "el BSP/raiz del sistema Yocto" "${YOCTO_DIR}/*.bsp" "${YOCTO_DIR}/core-image*.tar.zst" "${YOCTO_DIR}/core-image*.tar.gz" "${YOCTO_DIR}/mcore-image*.tar.zst" "${YOCTO_DIR}/mcore-image*.tar.gz" "${YOCTO_DIR}/*rootfs*.tar.zst" "${YOCTO_DIR}/*rootfs*.tar.gz") || exit 1

echo_note "WARNING" "[015] populate final boot tree with Limine ..."
mkdir -p "${CD_BOOT_DIR}" "${CD_LIMINE_DIR}" "${CD_EFI_BOOT_DIR}" "${CD_BSP_DIR}" "${CD_IMAGES_DIR}"

if [ ! -f "${INITRD_IMAGE}" ]; then
    echo_note "ERROR" "No existe ${INITRD_IMAGE}. Ejecuta primero ./_02-mk-bootdisk.sh o ./buildinstaller.sh --bootdisk"
    exit 1
fi

if [ ! -x "${LIMINE_DEPLOY}" ]; then
    echo_note "ERROR" "No se encuentra limine-deploy o no es ejecutable: ${LIMINE_DEPLOY}"
    exit 1
fi

if ! command -v xorriso >/dev/null 2>&1; then
    echo_note "ERROR" "No se ha encontrado xorriso en el sistema anfitrion."
    exit 1
fi

echo_note "WARNING" "#### Copying kernel and BSP artifacts ####"
copy_required_file "${KERNEL_SOURCE}" "${KERNEL_DEST}" "la imagen de kernel Yocto"
copy_required_file "${BSP_SOURCE}" "${BSP_DEST}" "el BSP de Yocto"

echo_note "WARNING" "#### Copying Limine runtime files ####"
copy_required_file "${LIMINE_DIR}/limine-bios-cd.bin" "${CD_LIMINE_DIR}/limine-bios-cd.bin" "limine-bios-cd.bin"
copy_required_file "${LIMINE_DIR}/limine-bios.sys" "${CD_LIMINE_DIR}/limine-bios.sys" "limine-bios.sys"
copy_required_file "${LIMINE_DIR}/limine-uefi-cd.bin" "${CD_LIMINE_DIR}/limine-uefi-cd.bin" "limine-uefi-cd.bin"
copy_required_file "${LIMINE_DIR}/BOOTX64.EFI" "${CD_EFI_BOOT_DIR}/BOOTX64.EFI" "BOOTX64.EFI"

echo_note "WARNING" "#### Writing Limine configuration ####"
write_limine_config "${LIMINE_CONF}"
cp -f "${LIMINE_CONF}" "${ROOT_LIMINE_CONF}"

echo_note "WARNING" "#### Creating bootable ISO image with Limine ####"
echo_note "WARNING" "Source directory: ${CD_TREE_DIR}"
echo_note "WARNING" "Output ISO: ${OUTPUT_ISO}"

# This command follows the official Limine documentation for creating a hybrid ISO.
# The paths for -b and -e are relative to the root of the CD_TREE_DIR.
#    -as mkisofs \                         # Usa xorriso en modo compatibilidad mkisofs
#   -r \                                   # Activa Rock Ridge (soporte de nombres largos en sistemas Unix)
#   -J \                                   # Activa Joliet (soporte de nombres largos en Windows)
#   -joliet-long \                         # Permite nombres Joliet más largos (hasta 103 caracteres)
#   -V 'Comodoo-Installer' \               # Establece la etiqueta/volumen de la ISO
#   -b boot/limine/limine-bios-cd.bin \    # Especifica el archivo de arranque BIOS (El Torito)
#   -no-emul-boot \                        # Sin emulación de disco (carga directa en memoria)
#   -boot-load-size 4 \                    # Número de sectores 512-bytes a cargar (4 = 2KB)
#   -boot-info-table \                     # Inserta tabla de información de arranque en el binario
#   -eltorito-alt-boot \                   # Inicia configuración alternativa de El Torito (UEFI)
#   -e boot/limine/limine-uefi-cd.bin \    # Especifica imagen de arranque UEFI
#   -no-emul-boot \                        # Sin emulación para UEFI
#   -isohybrid-gpt-basdat \                # Hace ISO arrancable en UEFI desde dispositivos USB/HD (hybrid mode)
#   -o "${OUTPUT_ISO}" \                   # Archivo de salida de la ISO
#   "${CD_TREE_DIR}"                       # Directorio raíz con contenido de la ISO

xorriso \
    -as mkisofs \
   -r \
   -J \
   -joliet-long \
   -V "${ISO_LABEL}" \
   -b boot/limine/limine-bios-cd.bin \
   -no-emul-boot \
   -boot-load-size 4 \
   -boot-info-table \
   -eltorito-alt-boot \
   -e boot/limine/limine-uefi-cd.bin \
   -no-emul-boot \
   -isohybrid-gpt-basdat \
   -o "${OUTPUT_ISO}" \
   "${CD_TREE_DIR}"

# CRITICAL STEP: Post-process the ISO with limine-deploy for BIOS boot.
echo_note "WARNING" "#### Running limine-deploy bios-install on the ISO ####"
"${LIMINE_DEPLOY}" bios-install "${OUTPUT_ISO}"

echo_note "OK" "#### ISO creation and deployment complete: ${OUTPUT_ISO} ####"
echo_note "OK" "#### You can now burn this file or test it with QEMU ####"
