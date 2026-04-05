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

# ── Force Spanish locale for Chromium and its utility subprocesses.
# Keep LANGUAGE as a priority chain for fallback.
export LANG="es_ES.UTF-8"
export LANGUAGE="es_ES:es"
export LC_MESSAGES="es_ES.UTF-8"

# ── Ensure DBus is properly configured (system bus).
# This reduces noise and prevents Chromium from trying alternative DBus paths.
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"

# ── Clean profile on every boot to avoid corruption/cache issues ────────────────
# (Chromium retains state from previous runs which can cause render failures).
if [ -d "${PROFILE_DIR}" ]; then
    rm -rf "${PROFILE_DIR}"
fi
mkdir -p "${PROFILE_DIR}"

# ── Common Chromium flags ─────────────────────────────────────────────────────
CHROMIUM_FLAGS=(
    --kiosk
    --no-first-run
    --no-default-browser-check
    --disable-infobars
    --disable-translate
    --lang=es-ES
    --accept-lang=es-ES,es
    --ozone-platform=wayland
    --enable-features=UseOzonePlatform
    --disable-background-networking
    --disable-component-update
    --disable-component-cloud-policy
    --disable-gcm
    --disable-session-crashed-bubble
    --disable-notifications
    --check-for-update-interval=31536000
    --log-level=3
    # Disable GPU rendering: more stable in VM/Wayland environments.
    # If hardware acceleration is needed later, remove this flag and add:
    #   --enable-gpu --use-vulkan=native
    --disable-gpu
    --disable-software-rasterizer
    # Extra safety: suppress translation and password-manager UI even if policy
    # loading is delayed/failed on first profile startup.
    --disable-features=MediaRouter,Translate,AutofillServerCommunication,OptimizationHints,OnDeviceModel,TranslateUI,PasswordManagerOnboarding,PasswordManagerEnableUPM,PasswordManagerSignInPromo
    --disable-save-password-bubble
    --disable-sync
    --password-store=basic
    --user-data-dir="${PROFILE_DIR}"
    --noerrdialogs
    --no-sandbox
    # POS hardening trade-off (requested): disable browser security barriers.
    --disable-web-security
    --allow-running-insecure-content
    --disable-site-isolation-trials
    --ignore-certificate-errors
    --allow-insecure-localhost
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

# ── Helper: check if Odoo is truly serving via its health endpoint ────────────
# Uses the official Odoo healthcheck endpoint (available since Odoo 14):
#   GET /web/health  →  HTTP 200  +  {"status": "pass"}
# This is lightweight, language-agnostic, and designed for this exact purpose.
odoo_is_ready() {
    local body
    body=$(wget -qO- --timeout=8 --tries=1 \
        "${ODOO_URL}/web/health" 2>/dev/null) || return 1
    echo "$body" | grep -Eqi 'pass|ok' || return 1
    return 0
}

# ── Helper: navigate Chromium to a new URL via DevTools HTTP API ──────────────
# Strategy: close the current splash tab, then open a new tab at the target URL.
# This avoids the need for the WebSocket protocol.
navigate_to() {
    local url="$1"
    local tab_info tab_id

    # Give DevTools a moment to be ready
    sleep 2

    tab_info=$(wget -qO- --timeout=5 --tries=1 \
        "http://127.0.0.1:${DEVTOOLS_PORT}/json" 2>/dev/null) || return 1

    # Extract the first tab id (the splash tab)
    tab_id=$(echo "$tab_info" \
        | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -1)

    # Close the existing tab (best-effort)
    if [ -n "$tab_id" ]; then
        wget -qO- --timeout=5 --tries=1 \
            "http://127.0.0.1:${DEVTOOLS_PORT}/json/close/${tab_id}" \
            >/dev/null 2>&1 || true
        sleep 1
    fi

    # Open a new tab pointing at Odoo; DevTools will make it the active tab
    wget -qO- --timeout=5 --tries=1 \
        "http://127.0.0.1:${DEVTOOLS_PORT}/json/new?${url}" \
        >/dev/null 2>&1 && return 0

    return 1
}

# ── Background watcher (first boot only): fallback poller via shell ───────────
# The splash page JavaScript is the primary mechanism: it polls /web/health
# directly from the browser and navigates when Odoo is ready.
# This shell watcher acts as a safety net in case the JS fetch is blocked
# (e.g. by browser security policy).  It uses the same /web/health endpoint
# and the DevTools API to close the splash tab and open Odoo in its place.
odoo_watcher() {
    echo "Watcher (fallback): esperando a que Odoo responda en ${ODOO_URL}/web/health ..."
    local i=0
    while [ "$i" -lt "$FIRST_BOOT_MAX_WAIT" ]; do
        if odoo_is_ready; then
            echo "Watcher: Odoo saludable — intentando navegar Chromium a ${ODOO_URL}"
            # Retry navigation up to 5 times (DevTools may not be ready yet)
            local nav_try=0
            while [ "$nav_try" -lt 5 ]; do
                if navigate_to "${ODOO_URL}"; then
                    echo "Watcher: Chromium navegado a Odoo correctamente."
                    return 0
                fi
                echo "Watcher: intento de navegación $((nav_try + 1)) fallido, reintentando en 5s..." >&2
                sleep 5
                nav_try=$((nav_try + 1))
            done
            echo "Watcher: no se pudo navegar Chromium tras 5 intentos." >&2
            return 1
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
    # Poll Odoo via real HTTP until it serves valid HTML (or timeout).
    echo "Arranque normal — esperando a Odoo via HTTP (max $((NORMAL_MAX_WAIT * NORMAL_INTERVAL))s) ..."
    i=0
    while [ "$i" -lt "$NORMAL_MAX_WAIT" ]; do
        if odoo_is_ready; then
            echo "Odoo responde con HTML válido — arrancando Chromium en ${ODOO_URL}"
            dismiss_psplash
            exec "$CHROMIUM_BIN" "${CHROMIUM_FLAGS[@]}" "$ODOO_URL"
        fi
        sleep "$NORMAL_INTERVAL"
        i=$((i + 1))
    done

    # Odoo didn't come up in time — open Chromium pointing at Odoo anyway
    # so the user sees Chromium's own retry/error page.
    echo "WARN: Odoo no respondió con HTML en $((NORMAL_MAX_WAIT * NORMAL_INTERVAL))s, abriendo Chromium igualmente." >&2
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

