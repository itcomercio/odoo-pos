#!/usr/bin/env bash

ISO_IMAGE="comodoo.iso"
KERNEL="CD/boot/vmlinuz"
INITRD="CD/boot/initrd.img"
DISK_IMAGE="c.img"

do_qcow2=false
mode=""

usage() {
    cat <<'EOF'
Uso: ./04-run-install.sh [--qcow2] [--install | --early | --boot]

  --qcow2   Fuerza la creacion de c.img con qemu-img.
  --install Lanza instalacion normal desde CDROM.
  --early   Lanza arranque de depuracion temprana con kernel/initrd + serial.
  --boot    Arranca el sistema ya instalado en el disco duro.
EOF
}

run_qcow2() {
    rm -f "$DISK_IMAGE"
    qemu-img create -f qcow2 "$DISK_IMAGE" 50000M
    # ver el tamaño:
    # qemu-img info c.img
}

run_install() {
    qemu-system-x86_64 \
        -k en-us \
        -hda "$DISK_IMAGE" \
        -cdrom "$ISO_IMAGE" \
        -boot d \
        -m size=4096 \
        -vga std
}

run_early() {
    qemu-system-x86_64 \
        -k en-us \
        -hda "$DISK_IMAGE" \
        -cdrom "$ISO_IMAGE" \
        -boot d \
        -m size=4096 \
        -kernel "$KERNEL" \
        -initrd "$INITRD" \
        -serial stdio \
        -append "console=ttyS0 rd.shell=0"
}

run_boot() {
    qemu-system-x86_64 -k en-us -hda "$DISK_IMAGE" -cpu host --accel kvm -m size=8192 -serial stdio
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --qcow2)
            do_qcow2=true
            ;;
        --install)
            if [ -n "$mode" ]; then
                usage
                exit 1
            fi
            mode="install"
            ;;
        --early)
            if [ -n "$mode" ]; then
                usage
                exit 1
            fi
            mode="early"
            ;;
        --boot)
            if [ -n "$mode" ]; then
                usage
                exit 1
            fi
            mode="boot"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
    shift
done

if [ "$do_qcow2" = true ] || [ ! -f "$DISK_IMAGE" ]; then
    run_qcow2
fi

case "$mode" in
    install)
        run_install
        ;;
    early)
        run_early
        ;;
    boot)
        run_boot
        ;;
    "")
        usage
        exit 1
        ;;
esac
