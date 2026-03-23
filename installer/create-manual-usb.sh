lsblk -o NAME,SIZE,MODEL,TRAN

# NAME          SIZE MODEL        TRAN
# sda          14.5G USB DISK 2.0 usb
# zram0           8G              
# nvme0n1     931.5G CT1000P2SSD8 nvme
# ├─nvme0n1p1   511M              nvme
# ├─nvme0n1p2   500M              nvme
# ├─nvme0n1p3     2M              nvme
# ├─nvme0n1p4   476M              nvme
# └─nvme0n1p5 930.1G              nvme

sudo umount /dev/sda
sudo dd if=comodoo.iso of=/dev/sda bs=4M status=progress oflag=sync conv=fsync
sync
sudo eject /dev/sda

