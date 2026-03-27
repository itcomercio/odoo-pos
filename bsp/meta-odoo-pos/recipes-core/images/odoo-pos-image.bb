SUMMARY = "Custom Odoo POS image"
DESCRIPTION = "Custom image recipe for Odoo POS based on core-image-weston"
LICENSE = "MIT"

require recipes-graphics/images/core-image-weston.bb

inherit extrausers

IMAGE_BASENAME = "odoo-pos-image"

# Also generate a compressed tar rootfs artifact.
IMAGE_FSTYPES:append = " tar.zst"

# Include PostgreSQL, bash, kiosk support assets, and Chromium Wayland browser.
IMAGE_INSTALL:append = " postgresql postgresql-server bash odoo-pos-kiosk chromium-ozone-wayland"

# Default root password: odoo
ROOT_PASSWORD_HASH = "\$6\$c6aQckAX4qXzO1vZ\$.GUniYswCC/RjUB5QCUTxnbM9g0.IhI4wKhtQa/hadwba368xN74WhFC3IhnUVwhk4zyg.J27dU2WZ2S.vsUQ0"

# Set the root shell to bash and provision a deterministic root password.
EXTRA_USERS_PARAMS = " \
	usermod -p '${ROOT_PASSWORD_HASH}' root; \
	usermod -s /bin/bash root; \
"
