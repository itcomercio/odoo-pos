#!/usr/bin/env bash
# vim: ts=4:sw=4:et:sts=4:ai:tw=80

usage () {
    cat <<'EOF'
Uso:
    ./buildinstaller.sh [--debug] [OPCIONES]

Opciones:
    --env         Ejecuta _01-mk-env.sh
    --bootdisk    Ejecuta _02-mk-bootdisk.sh
    --cdrom       Ejecuta _03-mk-cdrom.sh "${PWD}/CD"
    --install     Ejecuta _04-run-install.sh --install
    --install --early
                  Sub-opcion de --install: ejecuta _04-run-install.sh --early
    --boot        Ejecuta _04-run-install.sh --boot (arranca el SO instalado)
    --boot-serial Ejecuta _04-run-install.sh --boot-serial (arranque serial)
    --buildall    Ejecuta todas las fases: env, boot, cdrom e install
    --clean       Limpia artefactos temporales de trabajo
    --debug       Exporta DEBUG=--debug para los scripts llamados
    -h, --help    Muestra esta ayuda

Ejemplos:
    ./buildinstaller.sh --buildall
    ./buildinstaller.sh --env --bootdisk
    ./buildinstaller.sh --cdrom
    ./buildinstaller.sh --install
    ./buildinstaller.sh --install --early
    ./buildinstaller.sh --boot
    ./buildinstaller.sh --boot-serial
EOF
    exit 0
}

clean () {
    rm comodoo.iso
    rm c.img
    rm -fr CD
    rm -fr tmp
    rm -fr logs

    exit 0
}

#################
#    Main       #
#################

RUN_ENV=0
RUN_BOOTDISK=0
RUN_CDROM=0
RUN_INSTALL=0
INSTALL_MODE=""

while [ $# -gt 0 ]; do
    case $1 in
        -h|--help)
            usage
            ;;
        --debug)
            export DEBUG="--debug"
            shift
            ;;
        --clean)
            clean
            ;;
        --buildall)
            RUN_ENV=1
            RUN_BOOTDISK=1
            RUN_CDROM=1
            RUN_INSTALL=1
            INSTALL_MODE="install"
            shift
            ;;
        --env)
            RUN_ENV=1
            shift
            ;;
        --bootdisk)
            RUN_BOOTDISK=1
            shift
            ;;
        --cdrom)
            RUN_CDROM=1
            shift
            ;;
        --install)
            RUN_INSTALL=1
            if [ -z "$INSTALL_MODE" ]; then
                INSTALL_MODE="install"
            elif [ "$INSTALL_MODE" != "install" ]; then
                usage
                exit 1
            fi
            shift
            ;;
        --early)
            if [ "$RUN_INSTALL" -ne 1 ] || [ "$INSTALL_MODE" != "install" ]; then
                usage
                exit 1
            fi
            INSTALL_MODE="early"
            shift
            ;;
        --boot)
            if [ -n "$INSTALL_MODE" ] && [ "$INSTALL_MODE" != "boot" ]; then
                usage
                exit 1
            fi
            RUN_INSTALL=1
            INSTALL_MODE="boot"
            shift
            ;;
        --boot-serial)
            if [ -n "$INSTALL_MODE" ] && [ "$INSTALL_MODE" != "boot-serial" ]; then
                usage
                exit 1
            fi
            RUN_INSTALL=1
            INSTALL_MODE="boot-serial"
            shift
            ;;
        *)
            usage
            ;;
    esac
done

if [ "$RUN_ENV" -eq 0 ] && [ "$RUN_BOOTDISK" -eq 0 ] && [ "$RUN_CDROM" -eq 0 ] && [ "$RUN_INSTALL" -eq 0 ]; then
    usage
fi

if [ "$RUN_ENV" -eq 1 ]; then
    ./_01-mk-env.sh
fi

if [ "$RUN_BOOTDISK" -eq 1 ]; then
    ./_02-mk-bootdisk.sh
fi

if [ "$RUN_CDROM" -eq 1 ]; then
    ./_03-mk-cdrom.sh "${PWD}/CD"
fi

if [ "$RUN_INSTALL" -eq 1 ]; then
    case "$INSTALL_MODE" in
        install)
            ./_04-run-install.sh --install
            ;;
        early)
            ./_04-run-install.sh --early
            ;;
        boot)
            ./_04-run-install.sh --boot
            ;;
        boot-serial)
            ./_04-run-install.sh --boot-serial
            ;;
        *)
            usage
            exit 1
            ;;
    esac
fi

