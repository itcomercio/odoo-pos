# odoo-pos

Sistema de instalacion para un entorno POS basado en Yocto, con arranque de instalador desde ISO hibrida (BIOS/UEFI) usando Limine.

## Que es este proyecto

Este repositorio prepara un medio de instalacion (`comodoo.iso`) que arranca un entorno initrd con un instalador en Python (`installer/pyinstaller/instalador.py`).

Flujo general:

1. Preparar dependencias del host.
2. Construir `initrd.img` con `dracut`.
3. Construir una ISO booteable con Limine y artefactos Yocto.
4. Probar instalacion en QEMU sobre `c.img`.
5. Arrancar el sistema instalado desde ese disco virtual.

## Estructura principal

- `installer/buildinstaller.sh`: orquestador principal por fases.
- `installer/_01-mk-env.sh`: instala herramientas y dependencias (Fedora/dnf).
- `installer/_02-mk-bootdisk.sh`: genera `CD/boot/initrd.img`.
- `installer/_03-mk-cdrom.sh`: genera `comodoo.iso` con Limine.
- `installer/_04-run-install.sh`: ejecuta instalacion/pruebas en QEMU.
- `installer/pyinstaller/`: instalador que corre dentro del initrd.
- `installer/yocto/`: artefactos de kernel y rootfs/BSP.
- `installer/limine/`: binarios de Limine y `limine-deploy`.

## Requisitos del host

Segun los scripts actuales:

- Linux con `bash`.
- Entorno probado en Fedora (usa `dnf` en `_01-mk-env.sh`).
- Permisos `sudo` para instalar paquetes y crear artefactos del initrd.
- Herramientas de build/arranque: `dracut`, `xorriso`, `qemu-system-x86_64`, `qemu-img`, `grub2-tools`, etc.

> Nota: el script de entorno instala paquetes con nombres de Fedora. Si usas otra distro, tendras que adaptar dependencias manualmente.

## Artefactos necesarios (Yocto y Limine)

Antes de crear la ISO debes tener:

- Un kernel Yocto: `installer/yocto/bzImage*`.
- Un rootfs/BSP: `installer/yocto/*.bsp` o `core-image*.tar.zst|tar.gz`.
- Binarios Limine en `installer/limine/` (`limine-bios-cd.bin`, `limine-bios.sys`, `limine-uefi-cd.bin`, `BOOTX64.EFI`, `limine-deploy`).

Si faltan binarios Limine, revisa:

- `installer/limine/README.md`
- `installer/limine/download-limine.sh`

## Uso rapido

Desde `installer/`:

```bash
cd installer
./buildinstaller.sh --buildall
```

Esto intenta ejecutar todas las fases: entorno, initrd, ISO y arranque de instalacion en QEMU.

### Flujo recomendado paso a paso

```bash
cd installer
./buildinstaller.sh --env
./buildinstaller.sh --bootdisk
./buildinstaller.sh --cdrom
./buildinstaller.sh --install
```

Para arrancar despues del proceso de instalacion:

```bash
cd installer
./buildinstaller.sh --boot
```

## Opciones de `buildinstaller.sh`

- `--env`: instala dependencias del host.
- `--bootdisk`: crea `CD/boot/initrd.img`.
- `--cdrom`: crea `comodoo.iso` desde `CD/`.
- `--install`: arranca instalacion en QEMU desde ISO.
- `--install --early`: modo depuracion temprana (serial/kernel/initrd).
- `--boot`: arranca el sistema ya instalado desde `c.img`.
- `--buildall`: ejecuta todas las fases.
- `--clean`: borra artefactos (`comodoo.iso`, `c.img`, `CD/`, `tmp/`, `logs/`).
- `--debug`: exporta `DEBUG=--debug` para scripts llamados.

## Salidas esperadas

Tras un flujo correcto, en `installer/` deberias tener:

- `CD/boot/initrd.img`
- `CD/boot/vmlinuz`
- `CD/bsp/beetlepos-image-beetlepos.bsp` (o el artefacto detectado)
- `comodoo.iso`
- `c.img` (disco qcow2 para pruebas QEMU)

## Como funciona la instalacion (dentro del initrd)

El instalador Python (`installer/pyinstaller/instalador.py`) realiza, de forma automatica:

1. Seleccion de disco objetivo (actualmente fijo a `/dev/sda`).
2. Reparticionado completo del disco.
3. Formateo:
   - `/dev/sda1` -> `ext3` (boot)
   - `/dev/sda2` -> `swap`
   - `/dev/sda3` -> `ext3` (root)
4. Montaje de ISO en `/mnt/cdrom` y extraccion del BSP/rootfs.
5. Instalacion de GRUB BIOS (`grub2-install --target=i386-pc`).

## Advertencias importantes

- **Proceso destructivo:** el instalador borra y recrea particiones del disco objetivo.
- **Disco objetivo fijo:** el codigo actual usa `/dev/sda`.
- **Particionado fijo:** layout no parametrizable por CLI en el estado actual.
- **Modo GRUB BIOS:** orientado a `i386-pc`; revisa necesidades UEFI del sistema final.
- **Confianza de artefactos:** valida origen/checksum de `yocto/*` y binarios descargados.

## Troubleshooting rapido

- Falta `initrd.img` al crear ISO:
  - Ejecuta primero `./buildinstaller.sh --bootdisk`.
- Error por `xorriso` no encontrado:
  - Ejecuta `./buildinstaller.sh --env` o instala `xorriso` manualmente.
- No se encuentra kernel/BSP Yocto:
  - Revisa contenido de `installer/yocto/`.
- Falla `grub2-install` en instalador:
  - Verifica que el initrd incluye runtime GRUB (`/usr/lib/grub/i386-pc`).
- QEMU no arranca:
  - Verifica `qemu-system-x86_64`, `qemu-img` y presencia de `comodoo.iso`/`c.img`.

## Desarrollo y pruebas

Modo instalacion normal:

```bash
cd installer
./_04-run-install.sh --install
```

Modo depuracion temprana por serial:

```bash
cd installer
./_04-run-install.sh --early
```

Arranque del sistema instalado:

```bash
cd installer
./_04-run-install.sh --boot
```
