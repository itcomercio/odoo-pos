SUMMARY = "Custom Odoo POS image"
DESCRIPTION = "Custom image recipe for Odoo POS based on core-image-weston"
LICENSE = "MIT"

require recipes-graphics/images/core-image-weston.bb

inherit extrausers

IMAGE_BASENAME = "odoo-pos-image"

# Also generate a compressed tar rootfs artifact.
IMAGE_FSTYPES:append = " tar.zst"

# Suppress multiple-provider warning for weston-init.
PREFERRED_RPROVIDER_weston-init = "weston-init"

# Include Odoo container runtime, kiosk browser, and Chromium.
# odoo-container pulls in: podman, postgresql, postgresql-server, bash, shadow.
# iproute2-ss provides the ss command for network diagnostics (separate subpackage in Yocto).
IMAGE_INSTALL:append = " odoo-pos-kiosk chromium-ozone-wayland odoo-container iproute2 iproute2-ss"

# Default root password: odoo
ROOT_PASSWORD_HASH = "\$6\$c6aQckAX4qXzO1vZ\$.GUniYswCC/RjUB5QCUTxnbM9g0.IhI4wKhtQa/hadwba368xN74WhFC3IhnUVwhk4zyg.J27dU2WZ2S.vsUQ0"

# Set the root shell to bash and provision a deterministic root password.
EXTRA_USERS_PARAMS = " \
	usermod -p '${ROOT_PASSWORD_HASH}' root; \
	usermod -s /bin/bash root; \
"
