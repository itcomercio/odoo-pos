#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIMINE_DEPLOY="${SCRIPT_DIR}/limine/limine-deploy"

ISO_PATH="${1:-comodoo.iso}"
TARGET_DEV="${2:-/dev/sda}"

usage() {
	cat <<'EOF'
Uso:
  ./create-manual-usb.sh [ruta_iso] [dispositivo]

Ejemplo:
  ./create-manual-usb.sh comodoo.iso /dev/sda

Descripcion:
  Graba la ISO en el USB con dd y re-instala el bootloader Limine BIOS
  directamente sobre el dispositivo USB para garantizar arranque en PCs
  reales (BIOS y UEFI). Solo hacer dd no es suficiente para BIOS reales.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

if [ ! -f "$ISO_PATH" ]; then
	echo "[ERROR] No existe la ISO: $ISO_PATH" >&2
	exit 1
fi

if [ ! -b "$TARGET_DEV" ]; then
	echo "[ERROR] El destino no es un dispositivo de bloque: $TARGET_DEV" >&2
	exit 1
fi

# Verificar limine-deploy antes de empezar
if [ ! -x "$LIMINE_DEPLOY" ]; then
	echo "[ERROR] No se encuentra limine-deploy en: $LIMINE_DEPLOY" >&2
	echo "        Ejecuta primero: installer/limine/download-limine.sh" >&2
	exit 1
fi

TRANSPORT=$(lsblk -dn -o TRAN "$TARGET_DEV" | tr -d '[:space:]')
if [ "$TRANSPORT" != "usb" ]; then
	echo "[ERROR] El dispositivo no parece USB (TRAN=$TRANSPORT): $TARGET_DEV" >&2
	echo "        Revisa con: lsblk -o NAME,SIZE,MODEL,TRAN" >&2
	exit 1
fi

echo "[INFO] Dispositivos detectados:"
lsblk -o NAME,SIZE,MODEL,TRAN
echo
echo "[INFO] ISO a grabar : $ISO_PATH ($(du -h "$ISO_PATH" | cut -f1))"
echo "[WARN] DESTINO USB  : $TARGET_DEV  <-- SE BORRARA TODO"
echo

read -r -p "Escribe YES para continuar: " confirm
if [ "$confirm" != "YES" ]; then
	echo "[INFO] Operacion cancelada"
	exit 1
fi

read -r -p "Escribe el dispositivo exacto para confirmar ($TARGET_DEV): " confirm_dev
if [ "$confirm_dev" != "$TARGET_DEV" ]; then
	echo "[INFO] Confirmacion de dispositivo incorrecta. Cancelado."
	exit 1
fi

# --- Desmontar ---
echo "[INFO] Desmontando particiones de $TARGET_DEV"
while IFS= read -r part; do
	[ -n "$part" ] || continue
	sudo umount "$part" 2>/dev/null || true
done < <(lsblk -ln -o PATH "$TARGET_DEV" | tail -n +2)

# --- Grabar ISO ---
echo "[INFO] Grabando ISO con dd..."
sudo dd if="$ISO_PATH" of="$TARGET_DEV" bs=4M status=progress conv=fsync
sync
echo "[OK] dd completado."

# --- PASO CRITICO: reinstalar bootloader Limine BIOS en el USB ---
# El 'limine-deploy bios-install' sobre la ISO embebe el MBR bootcode en el
# fichero .iso, pero cuando hacemos dd a un USB el kernel/BIOS real requiere
# que ese codigo este instalado directamente en el dispositivo de bloque.
# Sin este paso, PCs reales con BIOS/CSM muestran cursor parpadeante y no arrancan.
echo "[INFO] Instalando bootloader Limine BIOS en el USB..."
sudo "${LIMINE_DEPLOY}" bios-install "${TARGET_DEV}"
echo "[OK] Limine BIOS instalado en ${TARGET_DEV}."

sync

# --- Verificacion post-escritura ---
echo ""
echo "[INFO] === Verificacion post-escritura ==="

echo "[INFO] Tabla de particiones del USB:"
sudo fdisk -l "$TARGET_DEV" | grep -v "^$" || true

ISO_BYTES=$(stat -c%s "$ISO_PATH")
CMP_BYTES=$(( ISO_BYTES < 67108864 ? ISO_BYTES : 67108864 ))
echo "[INFO] Comparando primeros $(( CMP_BYTES / 1048576 )) MiB ISO vs USB..."
if sudo cmp -n "$CMP_BYTES" "$ISO_PATH" "$TARGET_DEV" 2>/dev/null; then
	echo "[OK] Copia binaria verificada correctamente."
else
	echo "[WARN] Diferencia detectada en copia (esperado tras limine-deploy en USB)." >&2
fi

echo "[INFO] Estructura El Torito del USB:"
if command -v xorriso >/dev/null 2>&1; then
	xorriso -indev "$TARGET_DEV" -report_el_torito plain 2>/dev/null | grep -E "El Torito|Boot record|BIOS|UEFI" || true
else
	echo "[INFO] xorriso no disponible, omitiendo verificacion El Torito."
fi

# --- Expulsar ---
echo "[INFO] Expulsando dispositivo..."
sudo eject "$TARGET_DEV" || true

echo ""
echo "[OK] USB grabado y bootloader instalado correctamente: $TARGET_DEV"
echo "[OK] Deberia arrancar en BIOS (legacy/CSM) y UEFI."
