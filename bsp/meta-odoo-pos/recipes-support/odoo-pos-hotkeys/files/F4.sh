#!/bin/sh
set -eu

# Open cash drawer via ESC/POS command on USB thermal printer
printf '\033\160\000\031\372' > /dev/usb/lp0
logger -t odoo-pos-hotkeys "F1: cajon abierto"
