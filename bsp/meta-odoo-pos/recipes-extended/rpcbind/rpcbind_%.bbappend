# Keep rpcbind available if needed by NFS/RPC users, but do not auto-enable
# rpcbind.service / rpcbind.socket on Odoo POS images.
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

