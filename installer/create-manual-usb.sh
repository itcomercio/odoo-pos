#!/usr/bin/env bash
set -euo pipefail

ISO_PATH="${1:-comodoo.iso}"
TARGET_DEV="${2:-/dev/sda}"

usage() {
	cat <<'EOF'
Uso:
  ./create-manual-usb.sh [ruta_iso] [dispositivo]

Ejemplo:
  ./create-manual-usb.sh comodoo.iso /dev/sda
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

TRANSPORT=$(lsblk -dn -o TRAN "$TARGET_DEV" | tr -d '[:space:]')
if [ "$TRANSPORT" != "usb" ]; then
	echo "[ERROR] El dispositivo no parece USB (TRAN=$TRANSPORT): $TARGET_DEV" >&2
	echo "        Revisa con: lsblk -o NAME,SIZE,MODEL,TRAN" >&2
	exit 1
fi

echo "[INFO] Dispositivos detectados:"
lsblk -o NAME,SIZE,MODEL,TRAN
echo
echo "[WARN] Se va a sobrescribir COMPLETAMENTE: $TARGET_DEV"
echo "[WARN] ISO origen: $ISO_PATH"

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

echo "[INFO] Desmontando particiones de $TARGET_DEV"
while IFS= read -r part; do
	[ -n "$part" ] || continue
	sudo umount "$part" 2>/dev/null || true
done < <(lsblk -ln -o PATH "$TARGET_DEV" | tail -n +2)

echo "[INFO] Grabando ISO..."
sudo dd if="$ISO_PATH" of="$TARGET_DEV" bs=4M status=progress conv=fsync
sync

echo "[INFO] Expulsando dispositivo..."
sudo eject "$TARGET_DEV" || true

echo "[OK] USB grabado correctamente: $TARGET_DEV"

