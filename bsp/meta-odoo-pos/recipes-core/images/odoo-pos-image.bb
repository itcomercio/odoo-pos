SUMMARY = "Custom Odoo POS image"
DESCRIPTION = "Custom image recipe for Odoo POS based on core-image-weston"
LICENSE = "MIT"

require recipes-graphics/images/core-image-weston.bb

IMAGE_BASENAME = "odoo-pos-image"

# Include PostgreSQL server and client tools (psql) in the final image.
IMAGE_INSTALL:append = " postgresql postgresql-server"
