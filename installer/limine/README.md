# Limine Bootloader - Recursos del Instalador

Este directorio contiene los binarios y herramientas necesarios para integrar el gestor de arranque **Limine** en la imagen ISO de instalación del sistema Comodoo (basado en Yocto Project).

## ¿Qué es Limine?

[Limine](https://limine-bootloader.org/) es un gestor de arranque (bootloader) moderno, avanzado y portátil, diseñado para ser ligero, rápido y fácil de configurar.

A diferencia de gestores antiguos como **Syslinux** (limitado principalmente a BIOS legado) o **GRUB** (extremadamente complejo y pesado), Limine ofrece:

*   **Soporte Híbrido Real**: Funciona de manera nativa tanto en sistemas **Legacy BIOS** como en **UEFI** modernos de 64 bits.
*   **Protocolo de Arranque Limine**: Un protocolo propio eficiente, aunque también soporta el protocolo de arranque estándar de Linux.
*   **Configuración Unificada**: Utiliza un único fichero de configuración (`limine.cfg`) para ambos modos de arranque (BIOS y UEFI), simplificando enormemente el mantenimiento del instalador.

## ¿Por qué usamos Limine en este Instalador?

El objetivo del script `02-mk-bootdisk.sh` es generar una imagen ISO arrancable que permita instalar nuestra distribución Linux personalizada en un hardware de destino.

Necesitamos Limine por las siguientes razones críticas:

1.  **Arranque del Kernel Yocto**: Nuestra distribución genera un kernel (`bzImage`) y un sistema de archivos inicial (`initrd`). Limine es el encargado de cargar estos artefactos en la memoria RAM y transferir el control al kernel para iniciar el proceso de instalación (Stage 1 y Stage 2).
2.  **Compatibilidad de Hardware**: Los dispositivos de destino pueden variar desde TPVs antiguos (BIOS) hasta servidores o portátiles nuevos (UEFI). Limine nos permite crear una única ISO "híbrida" que arranca en ambos escenarios sin necesidad de mantener dos estructuras de arranque separadas.
3.  **Simplicidad en la ISO**: Al sustituir Syslinux, eliminamos la necesidad de estructuras complejas y parches para UEFI. Limine requiere solo unos pocos ficheros (`limine-bios.sys`, `limine-bios-cd.bin` y `BOOTX64.EFI`) para funcionar.

## Contenido y Scripts

### `download-limine.sh`

Este es un script de utilidad diseñado para automatizar la obtención de los binarios de Limine. Dado que no almacenamos binarios grandes en el repositorio git, este script realiza las siguientes tareas:

1.  Descarga la versión especificada de Limine (actualmente **v10.8.5**) desde el repositorio oficial en GitHub.
2.  Descomprime el archivo y extrae los componentes críticos:
    *   `limine-bios.sys`: El núcleo del bootloader para BIOS.
    *   `limine-bios-cd.bin`: El sector de arranque para imágenes CD/ISO en modo BIOS (El Torito).
    *   `BOOTX64.EFI`: La aplicación UEFI para arrancar en sistemas modernos.
3.  Compila la herramienta `limine-deploy` a partir del código fuente (`limine.c`) incluido en la descarga. Esta herramienta es necesaria para incrustar el bootloader en la imagen final si fuera necesario (aunque `xorriso` maneja gran parte de esto en la creación de la ISO).

### Uso

Antes de ejecutar el script principal de generación de disco (`02-mk-bootdisk.sh`), debes asegurarte de ejecutar una vez el script de descarga para poblar este directorio:

```bash
cd installer/limine
chmod +x download-limine.sh
./download-limine.sh
```

Una vez finalizado, verás los ficheros `.sys`, `.bin` y `.EFI` en este directorio, listos para ser copiados por el generador de la ISO.
