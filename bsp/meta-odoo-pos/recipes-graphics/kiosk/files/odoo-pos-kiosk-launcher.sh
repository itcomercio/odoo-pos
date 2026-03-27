#!/bin/sh
set -eu

URL="file:///usr/share/odoo-pos/kiosk/index.html"
BROWSER=""

for candidate in chromium chromium-browser cog wpewebkit MiniBrowser; do
    if command -v "$candidate" >/dev/null 2>&1; then
        BROWSER="$candidate"
        break
    fi
done

if [ -z "$BROWSER" ]; then
    echo "No supported browser binary found (chromium/chromium-browser/cog/wpewebkit/MiniBrowser)" >&2
    exit 1
fi

# Auto-discover the Wayland socket.  Weston may place it in different
# directories depending on how systemd/logind sets XDG_RUNTIME_DIR:
#   /run           -> forced by our weston.service drop-in (preferred)
#   /run/user/0    -> systemd-logind default for root
#   /tmp           -> fallback used by some embedded configs
SOCKET_FOUND=0
FOUND_XDG=""

for try_xdg in /run /run/user/0 /tmp; do
    i=0
    while [ "$i" -lt 20 ]; do
        if [ -S "${try_xdg}/wayland-0" ]; then
            FOUND_XDG="${try_xdg}"
            SOCKET_FOUND=1
            break
        fi
        sleep 0.5
        i=$((i + 1))
    done
    [ "$SOCKET_FOUND" -eq 1 ] && break
done

if [ "$SOCKET_FOUND" -eq 0 ]; then
    echo "Wayland socket not found in any known location after ~30s, aborting." >&2
    exit 1
fi

export XDG_RUNTIME_DIR="${FOUND_XDG}"
export WAYLAND_DISPLAY="wayland-0"

# Avoid inheriting a session DBus address format Chromium cannot parse in this
# system-service kiosk setup.
unset DBUS_SESSION_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE

# Keep Chromium profile data in a deterministic location instead of /tmp.
PROFILE_DIR="/var/lib/odoo-pos/chromium-profile"
mkdir -p "${PROFILE_DIR}"

echo "Using Wayland socket: ${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"

case "$BROWSER" in
    chromium|chromium-browser)
        CHROMIUM_BIN="$BROWSER"
        # /usr/bin/chromium is often a wrapper that injects extra flags.
        # Prefer the real binary for deterministic kiosk behavior.
        if [ -x /usr/lib/chromium/chromium-bin ]; then
            CHROMIUM_BIN="/usr/lib/chromium/chromium-bin"
        fi

        exec "$CHROMIUM_BIN" \
            --kiosk \
            --no-first-run \
            --no-default-browser-check \
            --disable-infobars \
            --ozone-platform=wayland \
            --enable-features=UseOzonePlatform \
            --disable-background-networking \
            --disable-component-update \
            --disable-dev-shm-usage \
            --disable-features=MediaRouter,Translate,AutofillServerCommunication,OptimizationHints,OnDeviceModel \
            --password-store=basic \
            --user-data-dir="${PROFILE_DIR}" \
            --noerrdialogs \
            --no-sandbox \
            "$URL"
        ;;
    cog)
        exec "$BROWSER" --platform=wayland --kiosk "$URL"
        ;;
    wpewebkit|MiniBrowser)
        exec "$BROWSER" "$URL"
        ;;
    *)
        echo "Unsupported browser launcher: $BROWSER" >&2
        exit 1
        ;;
esac

