#!/usr/bin/env bash

source include/functions.env

CD_ROOT="CD"
CD_BOOT_DIR="${CD_ROOT}/boot"
INITRD_IMAGE="${CD_BOOT_DIR}/initrd.img"

echo_note "WARNING" "#### Preparing CD tree ####"
mkdir -p "${CD_BOOT_DIR}"

echo_note "WARNING" "#### Removing previous initrd image ####"
sudo rm -f "${INITRD_IMAGE}"

PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
SITE_PKGS="/usr/lib/python${PY_VER}/site-packages"
GRUB_RUNTIME_DIR="/usr/lib/grub/i386-pc"

GRUB_INCLUDE_ARGS=()
if [ -d "$GRUB_RUNTIME_DIR" ]; then
    GRUB_INCLUDE_ARGS+=(--include "$GRUB_RUNTIME_DIR" "$GRUB_RUNTIME_DIR")
fi

echo_note "WARNING" "#### Building initrd image with dracut ####"
sudo dracut -f -v \
    -m "base bash" \
    --install "python3 bash ls cat mount mkdir dialog vim toe parted mkfs.ext4 mkswap grub2-install grub2-probe grub2-mkimage grub2-bios-setup" \
    --include "/usr/lib64/python${PY_VER}" "/usr/lib64/python${PY_VER}" \
    --include "/usr/lib/python${PY_VER}" "/usr/lib/python${PY_VER}" \
    --include "${SITE_PKGS}/dialog.py" "${SITE_PKGS}/dialog.py" \
    --include "/usr/lib64/libparted.so.2" "/usr/lib64/libparted.so.2" \
    --include "${PWD}/pyinstaller/instalador.py" "/usr/bin/instalador.py" \
    --include "${PWD}/pyinstaller/entrypoint.sh" "/lib/dracut/hooks/emergency/01-install.sh" \
    --include "/usr/share/terminfo" "/usr/share/terminfo" \
    "${GRUB_INCLUDE_ARGS[@]}" \
    "${INITRD_IMAGE}"

echo_note "WARNING" "#### Adjusting initrd image ownership ####"
sudo chown "${SUDO_USER:-$USER}:" "${INITRD_IMAGE}"

echo_note "OK" "#### initrd image created successfully ####"
