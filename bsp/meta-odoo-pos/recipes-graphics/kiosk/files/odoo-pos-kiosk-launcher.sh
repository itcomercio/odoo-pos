#!/bin/bash
set -eu

LOCAL_SPLASH="file:///usr/share/odoo-pos/kiosk/index.html"
PROFILE_DIR="/var/lib/odoo-pos/chromium-profile"

# Detect browser
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

# Prefer Spanish locale when generated on image; otherwise keep a valid UTF-8
# locale to avoid startup warnings in logs.
if locale -a 2>/dev/null | grep -qi '^es_ES\.utf\?8$'; then
    export LANG="es_ES.UTF-8"
else
    export LANG="C.UTF-8"
fi
export LANGUAGE="es_ES:es"

# Ensure DBus is properly configured (system bus).
# This reduces noise and prevents Chromium from trying alternative DBus paths.
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"

# Clean profile on every boot to avoid corruption/cache issues
# (Chromium retains state from previous runs which can cause render failures).
if [ -d "${PROFILE_DIR}" ]; then
    rm -rf "${PROFILE_DIR}"
fi
mkdir -p "${PROFILE_DIR}"

# Common Chromium flags
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
    --enable-wayland-ime
    --wayland-text-input-version=1
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

# Discover Wayland socket
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

# Helper: dismiss psplash boot splash
# Send QUIT command to psplash via its FIFO once Chromium has had a moment to
# paint the local splash page, minimizing any visible gap during hand-off.
dismiss_psplash() {
    local fifo="/run/psplash_fifo"
    if [ -e "$fifo" ]; then
        echo "QUIT" > "$fifo" 2>/dev/null || true
        echo "psplash dismissed"
    fi
}

echo "Iniciando Chromium con splash local persistente; la página gestionará /web/health."
(
    sleep 2
    dismiss_psplash
) &

exec "$CHROMIUM_BIN" "${CHROMIUM_FLAGS[@]}" "$LOCAL_SPLASH"

