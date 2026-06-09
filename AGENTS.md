# AGENTS.md

Este documento proporciona contexto e instrucciones para los agentes de programación de IA que trabajan en el proyecto **odoo-pos**.

## Descripción General del Proyecto
Este proyecto construye un sistema operativo basado en Yocto para sistemas POS de Odoo, incluyendo un instalador personalizado y un sistema de arranque ISO híbrido (BIOS/UEFI) utilizando Limine.

## Comandos de Configuración y Construcción
El proyecto se divide en dos áreas principales: `bsp/` (construcción del SO) e `installer/` (sistema de instalación).

### Configuración del Entorno
- Instalar dependencias en el host (basado en Fedora):
  ```bash
  cd installer && ./buildinstaller.sh --env
  ```

### Construcción de Yocto (BSP)
- Inicializar y construir la imagen de Yocto:
  ```bash
  cd bsp && ./yocto-bsp.sh --build
  ```
- Para preparar el entorno sin construir:
  ```bash
  cd bsp && ./yocto-bsp.sh --no-build
  ```

### Creación del Instalador e ISO
- Construir todo (initrd, ISO y ejecutar prueba en QEMU):
  ```bash
  cd installer && ./buildinstaller.sh --buildall
  ```
- Paso a paso:
  - Crear initrd: `./buildinstaller.sh --bootdisk`
  - Crear ISO: `./buildinstaller.sh --cdrom`
  - Ejecutar prueba de instalación: `./buildinstaller.sh --install`
  - Arrancar el sistema instalado: `./buildinstaller.sh --boot`

## Estilo de Código y Convenciones
- **Scripts de Shell:** Usar `bash`. Seguir los patrones existentes en `installer/*.sh` y `bsp/yocto-bsp.sh`. Preferir la modularidad y usar las funciones de `installer/include/functions.env`.
- **Python:** Utilizado para la lógica del instalador (`installer/pyinstaller/instalador.py`). Seguir PEP 8 siempre que sea posible.
- **Yocto/Bitbake:** Las recetas se encuentran en `bsp/meta-odoo-pos/`. Adherirse a las convenciones estándar de metadatos de OpenEmbedded.
- **Systemd:** Las unidades de servicio se encuentran en `bsp/meta-odoo-pos/recipes-*/files/`.

## Navegación del Proyecto
- `bsp/meta-odoo-pos/`: La capa principal de Yocto que contiene recetas personalizadas (Odoo, PostgreSQL, modo Kiosco, etc.).
- `installer/pyinstaller/`: Código fuente en Python para el instalador del sistema.
- `installer/yocto/`: Directorio para colocar los artefactos de construcción de Yocto (kernel, rootfs) antes de la creación de la ISO.
- `bsp/meta-odoo-pos/containers/`: Configuraciones de Podman/Docker para Odoo.

## Instrucciones de Pruebas
- Usar QEMU para probar el flujo completo de instalación mediante `./buildinstaller.sh --install`.
- Usar el flag `--early` para depuración temprana del arranque: `./buildinstaller.sh --install --early`.
- Revisar los logs en `installer/logs/` si falla algún paso de la construcción.

## Guía de Commits
- Usar mensajes de commit descriptivos.
- Formato: `área: descripción breve` (ej., `bsp: añadir nueva regla udev para impresoras` o `installer: corregir lógica de particionado de disco`).
