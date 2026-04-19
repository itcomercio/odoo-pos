#!/bin/sh
set -eu

KEY_NAME="${1:-}"
HOOK="/etc/triggerhappy/hooks/${KEY_NAME}.sh"

if [ -z "$KEY_NAME" ]; then
    logger -t odoo-pos-hotkeys "Missing key name argument"
    exit 1
fi

if [ -x "$HOOK" ]; then
    exec "$HOOK"
fi

logger -t odoo-pos-hotkeys "No executable hook for ${KEY_NAME} at ${HOOK}"
exit 0

