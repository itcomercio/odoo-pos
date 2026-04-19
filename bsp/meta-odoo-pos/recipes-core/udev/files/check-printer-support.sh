#!/bin/bash
# USB Printer Support Diagnostic Script for Odoo POS
# Run on target to verify thermal printer support is properly configured

echo "========================================"
echo "Odoo POS USB Printer Diagnostics"
echo "========================================"
echo ""

# ...existing code...

# 1. Check kernel module
echo "[1] Checking usblp kernel module..."
if lsmod | grep -q "^usblp "; then
    echo "    ✓ usblp module is LOADED"
else
    echo "    ✗ usblp module is NOT loaded"
    echo "    Attempting to load module..."
    if modprobe usblp 2>/dev/null; then
        echo "    ✓ Successfully loaded usblp"
    else
        echo "    ✗ FAILED to load usblp (may be compiled in-kernel)"
    fi
fi
echo ""

# 2. Check udev rules
echo "[2] Checking udev rules for USB printers..."
if [ -f /etc/udev/rules.d/99-odoo-pos-usb-printer.rules ]; then
    echo "    ✓ Odoo POS printer udev rules found"
    echo "    Rules content:"
    grep -v "^#" /etc/udev/rules.d/99-odoo-pos-usb-printer.rules | head -5
else
    echo "    ✗ Odoo POS printer udev rules NOT found"
fi
echo ""

# 3. Check USB libraries
echo "[3] Checking USB libraries..."
for lib in libusb libusb-1.0; do
    if ldconfig -p | grep -q "lib${lib}"; then
        echo "    ✓ ${lib} found"
    else
        echo "    ✗ ${lib} NOT found"
    fi
done
echo ""

# 4. Check utilities
echo "[4] Checking USB utilities..."
for cmd in lsusb usbhid-dump; do
    if command -v $cmd &>/dev/null; then
        echo "    ✓ $cmd available"
    else
        echo "    ✗ $cmd NOT found"
    fi
done
echo ""

# 5. Check CUPS
echo "[5] Checking CUPS printer support..."
if systemctl is-active cups >/dev/null 2>&1; then
    echo "    ✓ CUPS daemon is RUNNING"
else
    echo "    ✗ CUPS daemon is NOT running"
    echo "    Starting CUPS..."
    if systemctl start cups; then
        echo "    ✓ CUPS started successfully"
    else
        echo "    ✗ Failed to start CUPS"
    fi
fi
echo ""

# 6. List connected USB devices
echo "[6] Connected USB devices:"
if command -v lsusb &>/dev/null; then
    lsusb
else
    echo "    lsusb not available"
fi
echo ""

# 7. Check /dev/usb/lp* devices
echo "[7] Checking for USB printer device nodes..."
if ls /dev/usb/lp* 2>/dev/null; then
    echo "    ✓ USB printer device(s) found:"
    ls -la /dev/usb/lp*
else
    echo "    ✗ No USB printer device nodes found"
    echo "    (Connect a USB printer and udev will create /dev/usb/lp* devices)"
fi
echo ""

echo "========================================"
echo "End of diagnostics"
echo "========================================"

