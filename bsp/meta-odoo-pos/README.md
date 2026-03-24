This layer contains Odoo POS customizations for Yocto.

Layer name
==========

  meta-odoo-pos

How to add the layer
====================

From the workspace root (where `bitbake-builds/` is generated):

  bitbake-layers add-layer meta-odoo-pos

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

  source bitbake-builds/poky-master/build/init-build-env
  bitbake-config-build disable-fragment distro/poky
  bitbake-layers add-layer meta-odoo-pos
  export DISTRO=odoo-pos-system
  bitbake odoo-pos-image

If your build tree was already initialized with:

  ./bitbake/bin/bitbake-setup init --non-interactive poky-master poky-with-sstate distro/poky machine/qemux86-64

you must disable the builtin `distro/poky` fragment before setting `DISTRO`,
otherwise BitBake will abort with a fragment conflict.

Custom image recipe
===================

This layer also provides a custom image recipe at:

  meta-odoo-pos/recipes-core/images/odoo-pos-image.bb

The image is currently a thin wrapper around `core-image-weston`, so it is
a good starting point for adding Odoo POS packages and further customizations.
