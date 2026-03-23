#!/bin/bash
# Forzar montajes si no están (en emergency suelen estar ya)
[ -d /proc/1 ] || mount -t proc proc /proc >/dev/null 2>&1
[ -d /sys/kernel ] || mount -t sysfs sys /sys >/dev/null 2>&1

echo "###################"
echo "!!! INSTALACIÓN !!!"
echo "###################"

/usr/bin/python3 /usr/bin/instalador.py

# Al terminar el Python, nos quedamos en un bash para que no se reinicie
exec /bin/bash
