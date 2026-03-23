#!/usr/bin/env bash
#
# Script to download and prepare Limine binaries (v10.8.5-binary).
#

set -e

# Configuration
LIMINE_VERSION="10.8.5-binary"
LIMINE_ZIP="v${LIMINE_VERSION}.zip"
LIMINE_URL="https://github.com/Limine-Bootloader/Limine/archive/refs/tags/${LIMINE_ZIP}"
EXTRACTED_DIR_NAME="Limine-${LIMINE_VERSION}"

# Check for required tools
for tool in wget unzip gcc; do
    if ! command -v $tool >/dev/null 2>&1; then
        echo "Error: '$tool' is required but not installed."
        exit 1
    fi
done

echo "Downloading Limine (${LIMINE_VERSION})..."
rm -rf "${EXTRACTED_DIR_NAME}" "${LIMINE_ZIP}"
wget -O "${LIMINE_ZIP}" "${LIMINE_URL}"

echo "Extracting..."
unzip -q "${LIMINE_ZIP}"

echo "Preparing binaries from '${EXTRACTED_DIR_NAME}'..."

copy_file() {
    local source_file_name="$1"
    local dest_file_name="$2"
    local found_path=$(find "${EXTRACTED_DIR_NAME}" -name "${source_file_name}" | head -n 1)

    if [ -n "$found_path" ]; then
        echo "Copying '${source_file_name}' -> '${dest_file_name}'..."
        cp -v "${found_path}" "./${dest_file_name}"
    else
        echo "Error: '${source_file_name}' not found in the archive."
        exit 1
    fi
}

# Copy bootloader files
copy_file "limine-bios.sys" "limine-bios.sys"
copy_file "limine-bios-cd.bin" "limine-bios-cd.bin"
copy_file "limine-uefi-cd.bin" "limine-uefi-cd.bin" # <-- Added this line
copy_file "BOOTX64.EFI" "BOOTX64.EFI"

# Compile limine-deploy tool
echo "Building limine-deploy tool..."
LIMINE_C_SRC=$(find "${EXTRACTED_DIR_NAME}" -name "limine.c" | head -n 1)
if [ -n "$LIMINE_C_SRC" ]; then
    gcc -O2 -pipe "${LIMINE_C_SRC}" -o limine-deploy
    echo "limine-deploy compiled successfully."
fi

echo "Cleaning up..."
rm -rf "${EXTRACTED_DIR_NAME}"
rm -f "${LIMINE_ZIP}"

echo "------------------------------------------------"
echo "Limine setup complete. Files ready:"
ls -l limine-*.sys limine-*.bin BOOTX64.EFI limine-deploy
echo "------------------------------------------------"
