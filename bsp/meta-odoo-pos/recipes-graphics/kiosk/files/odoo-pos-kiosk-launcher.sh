#!/bin/sh
set -eu

# Odoo web interface running locally.
ODOO_HOST="127.0.0.1"
ODOO_PORT="8069"
ODOO_URL="http://localhost:${ODOO_PORT}"
LOCAL_FALLBACK="file:///usr/share/odoo-pos/kiosk/index.html"
URL=""
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

# ── Wait for Odoo HTTP endpoint ───────────────────────────────────────────────
# Odoo can take a significant time on first boot (database initialisation).
# We poll the port with a simple TCP connect via Python (always present).
# Maximum wait: 60 × 5 s = 5 minutes.
# If Odoo never becomes ready, fall back to the local placeholder page.
echo "Waiting for Odoo at ${ODOO_URL} ..."
ODOO_READY=0
i=0
while [ "$i" -lt 60 ]; do
    if python3 -c "
import socket, sys
try:
    s = socket.create_connection(('${ODOO_HOST}', ${ODOO_PORT}), timeout=2)
    s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        ODOO_READY=1
        break
    fi
    sleep 5
    i=$((i + 1))
done

if [ "$ODOO_READY" -eq 1 ]; then
    URL="${ODOO_URL}"
    echo "Odoo ready — launching kiosk browser."
else
    URL="${LOCAL_FALLBACK}"
    echo "WARNING: Odoo did not become ready after 5 minutes; launching browser with local fallback page." >&2
fi

# Auto-discover the Wayland socket.  Weston may place it in different
# directories depending on how systemd/logind sets XDG_RUNTIME_DIR:
#   /run/user/<weston-uid>  -> systemd-logind default for the weston user
#   /run/user/0             -> systemd-logind default for root
#   /run                    -> legacy embedded configs
#   /tmp                    -> fallback used by some embedded configs

# Build the list of candidate directories dynamically.
WESTON_UID=$(id -u weston 2>/dev/null || true)
SEARCH_DIRS=""
if [ -n "$WESTON_UID" ]; then
    SEARCH_DIRS="/run/user/${WESTON_UID}"
fi
SEARCH_DIRS="${SEARCH_DIRS} /run/user/0 /run /tmp"

SOCKET_FOUND=0
FOUND_XDG=""

for try_xdg in $SEARCH_DIRS; do
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

