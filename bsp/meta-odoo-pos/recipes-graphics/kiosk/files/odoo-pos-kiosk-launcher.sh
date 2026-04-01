#!/bin/bash
set -eu

# ── Configuration ─────────────────────────────────────────────────────────────
ODOO_HOST="127.0.0.1"
ODOO_PORT="8069"
ODOO_URL="http://localhost:${ODOO_PORT}"
LOCAL_SPLASH="file:///usr/share/odoo-pos/kiosk/index.html"
DEVTOOLS_PORT="9222"
PROFILE_DIR="/var/lib/odoo-pos/chromium-profile"

# Marker created by odoo-container-import.sh after a successful podman load.
# If it exists the heavy first-boot import is already done.
IMPORT_MARKER="/var/lib/odoo/.odoo-container-imported"

# First boot: 720 × 5s = 60 min (podman load + Odoo DB init).
# Normal boot: 120 × 2s =  4 min (just Odoo startup).
FIRST_BOOT_MAX_WAIT=720
FIRST_BOOT_INTERVAL=5
NORMAL_MAX_WAIT=120
NORMAL_INTERVAL=2

# ── Detect browser ────────────────────────────────────────────────────────────
BROWSER=""
for candidate in chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
        BROWSER="$candidate"
        break
    fi
done
if [ -z "$BROWSER" ]; then
    echo "No supported browser binary found (chromium/chromium-browser)" >&2
    exit 1
fi

# Prefer the real binary over the wrapper script.
CHROMIUM_BIN="$BROWSER"
if [ -x /usr/lib/chromium/chromium-bin ]; then
    CHROMIUM_BIN="/usr/lib/chromium/chromium-bin"
fi

# ── Common Chromium flags ─────────────────────────────────────────────────────
CHROMIUM_FLAGS=(
    --kiosk
    --no-first-run
    --no-default-browser-check
    --disable-infobars
    --disable-translate
    --lang=es
    --ozone-platform=wayland
    --enable-features=UseOzonePlatform
    --disable-background-networking
    --disable-component-update
    --disable-dev-shm-usage
    --disable-features=MediaRouter,Translate,AutofillServerCommunication,OptimizationHints,OnDeviceModel,TranslateUI
    --password-store=basic
    --user-data-dir="${PROFILE_DIR}"
    --noerrdialogs
    --no-sandbox
)

# ── Discover Wayland socket ───────────────────────────────────────────────────
WESTON_UID=$(id -u weston 2>/dev/null || true)
SEARCH_DIRS=""
[ -n "$WESTON_UID" ] && SEARCH_DIRS="/run/user/${WESTON_UID}"
SEARCH_DIRS="${SEARCH_DIRS} /run/user/0 /run /tmp"

FOUND_XDG=""
for try_xdg in $SEARCH_DIRS; do
    i=0
    while [ "$i" -lt 20 ]; do
        if [ -S "${try_xdg}/wayland-0" ]; then
            FOUND_XDG="${try_xdg}"
            break 2
        fi
        sleep 0.5
        i=$((i + 1))
    done
done

if [ -z "$FOUND_XDG" ]; then
    echo "Wayland socket not found after ~30s, aborting." >&2
    exit 1
fi

export XDG_RUNTIME_DIR="${FOUND_XDG}"
export WAYLAND_DISPLAY="wayland-0"
unset DBUS_SESSION_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE
mkdir -p "${PROFILE_DIR}"

echo "Wayland socket: ${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"

# ── Helper: dismiss psplash boot splash ────────────────────────────────────────
# Send QUIT command to psplash via its FIFO just before Chromium takes over
# the framebuffer.  This ensures no gap between the boot splash and the kiosk UI.
dismiss_psplash() {
    local fifo="/run/psplash_fifo"
    if [ -e "$fifo" ]; then
        echo "QUIT" > "$fifo" 2>/dev/null || true
        echo "psplash dismissed"
    fi
}

# ── Helper: check if Odoo TCP port is open ────────────────────────────────────
odoo_is_ready() {
    (echo >/dev/tcp/${ODOO_HOST}/${ODOO_PORT}) 2>/dev/null
}

# ── Helper: navigate Chromium to a new URL via DevTools ───────────────────────
navigate_to() {
    local url="$1"
    local tab_info tab_id

    tab_info=$(wget -qO- "http://127.0.0.1:${DEVTOOLS_PORT}/json" 2>/dev/null) || return 1
    tab_id=$(echo "$tab_info" | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -1)
    [ -z "$tab_id" ] && return 1

    wget -qO- "http://127.0.0.1:${DEVTOOLS_PORT}/json/navigate/${tab_id}?url=${url}" >/dev/null 2>&1
}

# ── Background watcher (first boot only): poll Odoo, then navigate ────────────
odoo_watcher() {
    echo "Watcher: esperando a que Odoo esté disponible en ${ODOO_URL} (primer arranque) ..."
    local i=0
    while [ "$i" -lt "$FIRST_BOOT_MAX_WAIT" ]; do
        if odoo_is_ready; then
            echo "Watcher: Odoo accesible en puerto ${ODOO_PORT} — navegando a ${ODOO_URL}"
            sleep 3
            if navigate_to "${ODOO_URL}"; then
                echo "Watcher: Chromium navegado a Odoo correctamente."
            else
                echo "Watcher: reintentando navegación DevTools..." >&2
                sleep 5
                navigate_to "${ODOO_URL}" || echo "Watcher: segundo intento fallido." >&2
            fi
            return 0
        fi
        sleep "$FIRST_BOOT_INTERVAL"
        i=$((i + 1))
    done
    echo "Watcher: Odoo no respondió tras $((FIRST_BOOT_MAX_WAIT * FIRST_BOOT_INTERVAL))s." >&2
    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN: decide between first-boot (splash + watcher) and normal boot (direct).
# ══════════════════════════════════════════════════════════════════════════════

if [ -f "${IMPORT_MARKER}" ]; then
    # ── Normal boot: container already imported ───────────────────────────────
    # Wait a short time for Odoo to be ready (typically a few seconds).
    echo "Arranque normal — esperando brevemente a Odoo ..."
    i=0
    while [ "$i" -lt "$NORMAL_MAX_WAIT" ]; do
        if odoo_is_ready; then
            echo "Odoo listo — arrancando Chromium apuntando a ${ODOO_URL}"
            dismiss_psplash
            exec "$CHROMIUM_BIN" "${CHROMIUM_FLAGS[@]}" "$ODOO_URL"
        fi
        sleep "$NORMAL_INTERVAL"
        i=$((i + 1))
    done

    # Odoo didn't come up in time — launch with Odoo URL anyway so that
    # Chromium shows its own error/retry page rather than an old splash.
    echo "WARN: Odoo no respondió en $((NORMAL_MAX_WAIT * NORMAL_INTERVAL))s, abriendo Chromium igualmente." >&2
    dismiss_psplash
    exec "$CHROMIUM_BIN" "${CHROMIUM_FLAGS[@]}" "$ODOO_URL"
else
    # ── First boot: podman load is running in parallel ────────────────────────
    echo "Primer arranque detectado — mostrando splash mientras se carga el sistema"

    # Launch watcher in background; it will navigate Chromium when Odoo is up.
    odoo_watcher &

    # Dismiss the Yocto boot splash right before Chromium paints the kiosk splash.
    dismiss_psplash

    # Start Chromium immediately with the splash page + DevTools port enabled.
    exec "$CHROMIUM_BIN" "${CHROMIUM_FLAGS[@]}" \
        --remote-debugging-port="${DEVTOOLS_PORT}" \
        "$LOCAL_SPLASH"
fi

