This layer contains Odoo POS customizations for Yocto.

Layer name
==========

  meta-odoo-pos

How to add the layer
====================

The recommended flow is to use the bootstrap script from `bsp/`:

  cd /home/javiroman/HACK/dev/itc-github/public/odoo-pos.git/bsp
  ./yocto-bsp.sh --build

To prepare the build environment without starting BitBake immediately:

  cd /home/javiroman/HACK/dev/itc-github/public/odoo-pos.git/bsp
  ./yocto-bsp.sh --no-build

Systemd customization in this layer
===================================

This layer provides a distro config at:

  meta-odoo-pos/conf/distro/odoo-pos-system.conf

The distro is based on poky and applies:

- systemd as init manager
- sysvinit removal from DISTRO_FEATURES
- RPM package format (package_rpm)
- virtualization/seccomp features for container runtime

Additional layer dependency
===========================

This project now runs Odoo inside a container runtime. The bootstrap script
also adds:

- `meta-virtualization` (for Podman and related container stack)
- `meta-browser/meta-chromium` (for kiosk browser)

Build using this distro
=======================

  cd /home/javiroman/HACK/dev/itc-github/public/odoo-pos.git/bsp
  ./yocto-bsp.sh --build

If your build tree was already initialized with:

  ./bitbake/bin/bitbake-setup init --non-interactive poky-master poky-with-sstate distro/poky machine/qemux86-64

you must disable the builtin `distro/poky` fragment before setting `DISTRO`,
otherwise BitBake will abort with a fragment conflict.

`yocto-bsp.sh` already performs that step, adds `meta-odoo-pos`, updates
`local.conf` with `DISTRO = "odoo-pos-system"`, and can build
`odoo-pos-image` automatically.

With `--no-build`, it performs the same setup steps but skips the final
`bitbake odoo-pos-image` invocation so you can run it manually later.

With `--build`, it performs the setup and then runs `bitbake odoo-pos-image`.

Custom image recipe
===================

This layer also provides a custom image recipe at:

  meta-odoo-pos/recipes-core/images/odoo-pos-image.bb

The image wraps `core-image-weston` and adds:

- PostgreSQL server/client
- kiosk package and Chromium
- `odoo-container` package (systemd + Podman runtime)

Containerized Odoo runtime
==========================

Odoo is started via systemd unit `odoo.service`, which launches a Podman
container and connects to host PostgreSQL.

Recipe:

  meta-odoo-pos/recipes-odoo/odoo-container/odoo-container_1.0.bb

Key runtime files installed by that recipe:

- `/etc/default/odoo-container` (image reference and runtime options)
- `/etc/odoo/odoo.conf` (Odoo config mounted into container)
- `/etc/containers/containers.conf` and `/etc/containers/storage.conf` (Podman config)
- `/usr/bin/odoo-container-launch.sh` (container launcher)
- `odoo.service` and `postgresql-odoo-setup.service`

Custom Odoo image build pipeline
================================

This repository also provides a host-side pipeline to build a custom Odoo
container image from a local Dockerfile and embed it into the Yocto rootfs.

Build context:

  meta-odoo-pos/containers/odoo/<version>/

Integrated host build/export command:

  cd /home/javiroman/HACK/dev/itc-github/public/odoo-pos.git/bsp
  ./yocto-bsp.sh --build-odoo-container-image

That Yocto bootstrap parameter:

- builds image tag `localhost/odoo-pos:19.0`
- exports it to:

  meta-odoo-pos/recipes-odoo/odoo-container/files/odoo-image.tar

- generates a Podman storage snapshot for rootfs preinstall:

  meta-odoo-pos/recipes-odoo/odoo-container/files/odoo-storage-vfs.tar.zst

The `odoo-container` recipe installs that storage snapshot directly into
`/var/lib/containers/storage` in the final rootfs, so `podman images` and
`podman run` work immediately after boot without any load step.
`odoo-image.tar` is an intermediate host-side artifact and is not shipped in the rootfs.

You can also combine both steps in one command:

  ./yocto-bsp.sh --build-odoo-container-image --build

Kiosk mode customization
========================

This layer now adds a kiosk package at:

  meta-odoo-pos/recipes-graphics/kiosk/odoo-pos-kiosk_1.0.bb

It installs:

- `/etc/xdg/weston/weston.ini` with `kiosk-shell.so`
- `odoo-pos-kiosk.service` (systemd auto-start)
- `/usr/bin/odoo-pos-kiosk-launcher.sh`
- `/usr/share/odoo-pos/kiosk/index.html`

The launcher opens Chromium in kiosk mode pointing to local Odoo HTTP:

  http://localhost:8069

If your Yocto setup does not provide a `chromium` package in current layers,
replace that package in `odoo-pos-image.bb` with the browser available in your
build configuration.

