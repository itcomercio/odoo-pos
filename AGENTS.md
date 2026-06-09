# AGENTS.md

This document provides context and instructions for AI coding agents working on the **odoo-pos** project.

## Project Overview
This project builds a Yocto-based OS for Odoo POS systems, including a custom installer and a hybrid ISO (BIOS/UEFI) boot system using Limine.

## Setup & Build Commands
The project is divided into two main areas: `bsp/` (OS build) and `installer/` (Installation system).

### Environment Setup
- Install host dependencies (Fedora-based):
  ```bash
  cd installer && ./buildinstaller.sh --env
  ```

### Yocto Build (BSP)
- Initialize and build the Yocto image:
  ```bash
  cd bsp && ./yocto-bsp.sh --build
  ```
- To prepare the environment without building:
  ```bash
  cd bsp && ./yocto-bsp.sh --no-build
  ```

### Installer & ISO Creation
- Build everything (initrd, ISO, and run QEMU test):
  ```bash
  cd installer && ./buildinstaller.sh --buildall
  ```
- Step-by-step:
  - Create initrd: `./buildinstaller.sh --bootdisk`
  - Create ISO: `./buildinstaller.sh --cdrom`
  - Run installation test: `./buildinstaller.sh --install`
  - Boot installed system: `./buildinstaller.sh --boot`

## Code Style & Conventions
- **Shell Scripts:** Use `bash`. Follow existing patterns in `installer/*.sh` and `bsp/yocto-bsp.sh`. Prefer modularity and use functions from `installer/include/functions.env`.
- **Python:** Used for the installer logic (`installer/pyinstaller/instalador.py`). Follow PEP 8 where possible.
- **Yocto/Bitbake:** Recipes are located in `bsp/meta-odoo-pos/`. Adhere to standard OpenEmbedded metadata conventions.
- **Systemd:** Service units are found in `bsp/meta-odoo-pos/recipes-*/files/`.

## Project Navigation
- `bsp/meta-odoo-pos/`: The main Yocto layer containing custom recipes (Odoo, PostgreSQL, Kiosk mode, etc.).
- `installer/pyinstaller/`: Python source for the system installer.
- `installer/yocto/`: Directory for placing Yocto build artifacts (kernel, rootfs) before ISO creation.
- `bsp/meta-odoo-pos/containers/`: Podman/Docker configurations for Odoo.

## Testing Instructions
- Use QEMU for testing the full installation flow via `./buildinstaller.sh --install`.
- Use `--early` flag for early boot debugging: `./buildinstaller.sh --install --early`.
- Check logs in `installer/logs/` if a build step fails.

## Commit Guidelines
- Use descriptive commit messages.
- Format: `area: brief description` (e.g., `bsp: add new udev rule for printers` or `installer: fix disk partitioning logic`).
