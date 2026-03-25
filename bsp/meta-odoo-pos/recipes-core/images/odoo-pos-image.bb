SUMMARY = "Custom Odoo POS image"
DESCRIPTION = "Custom image recipe for Odoo POS based on core-image-weston"
LICENSE = "MIT"

require recipes-graphics/images/core-image-weston.bb

inherit extrausers

IMAGE_BASENAME = "odoo-pos-image"

# Also generate a compressed tar rootfs artifact.
IMAGE_FSTYPES:append = " tar.zst"

# Include PostgreSQL server/client tools and bash in the final image.
IMAGE_INSTALL:append = " postgresql postgresql-server bash"

# Use bash as the default login shell for root.
EXTRA_USERS_PARAMS = "usermod -s /bin/bash root;"
