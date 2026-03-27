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

# Wait briefly for the Weston Wayland socket.
i=0
while [ "$i" -lt 40 ]; do
    if [ -S "/run/wayland-0" ]; then
        break
    fi
    sleep 0.25
    i=$((i + 1))
done

case "$BROWSER" in
    chromium|chromium-browser)
        exec "$BROWSER" \
            --kiosk \
            --no-first-run \
            --disable-infobars \
            --ozone-platform=wayland \
            --enable-features=UseOzonePlatform \
            --noerrdialogs \
            --no-sandbox \
            "$URL"
        ;;
    cog)
        exec "$BROWSER" --platform=wayland --kiosk "$URL"
        ;;
    wpewebkit)
        exec "$BROWSER" "$URL"
        ;;
    MiniBrowser)
        exec "$BROWSER" "$URL"
        ;;
    *)
        echo "Unsupported browser launcher: $BROWSER" >&2
        exit 1
        ;;
esac

