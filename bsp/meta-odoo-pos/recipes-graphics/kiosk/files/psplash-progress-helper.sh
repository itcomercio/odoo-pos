#!/bin/sh
set -eu

FIFO="/run/psplash_fifo"
LAST=-1

# Wait briefly for psplash FIFO to appear.
for _ in $(seq 1 10); do
    [ -p "$FIFO" ] && break
    sleep 0.2
done

[ -p "$FIFO" ] || exit 0

while :; do
    # Manager.Progress returns a float in [0,1].
    raw_progress=$(systemctl show -p Progress --value 2>/dev/null || echo "")
    [ -n "$raw_progress" ] || raw_progress="0"

    percent=$(awk -v p="$raw_progress" 'BEGIN {
        if (p < 0) p = 0;
        if (p > 1) p = 1;
        printf "%d", (p * 100);
    }')

    if [ "$percent" -gt "$LAST" ]; then
        # psplash command protocol expects NUL-terminated commands.
        printf 'PROGRESS %s\0' "$percent" > "$FIFO" 2>/dev/null || exit 0
        LAST="$percent"
    fi

    sleep 1
done

