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

The image is currently a thin wrapper around `core-image-weston`, so it is
a good starting point for adding Odoo POS packages and further customizations.

Kiosk mode customization
========================

This layer now adds a kiosk package at:

  meta-odoo-pos/recipes-graphics/kiosk/odoo-pos-kiosk_1.0.bb

It installs:

- `/etc/xdg/weston/weston.ini` with `kiosk-shell.so`
- `odoo-pos-kiosk.service` (systemd auto-start)
- `/usr/bin/odoo-pos-kiosk-launcher.sh`
- `/usr/share/odoo-pos/kiosk/index.html`

The launcher opens Chromium in kiosk mode pointing to:

  file:///usr/share/odoo-pos/kiosk/index.html

If your Yocto setup does not provide a `chromium` package in current layers,
replace that package in `odoo-pos-image.bb` with the browser available in your
build configuration.

