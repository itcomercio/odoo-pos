# The POS image does not need persistent ip6tables restore at boot.
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

