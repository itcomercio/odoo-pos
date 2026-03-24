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

  meta-odoo-pos/conf/distro/odoo-pos-systemd.conf

The distro is based on poky and applies:

- systemd as init manager
- sysvinit removal from DISTRO_FEATURES
- RPM package format (package_rpm)

Build using this distro
=======================

  source bitbake-builds/poky-master/build/init-build-env
  export DISTRO=odoo-pos-systemd
  bitbake core-image-weston
