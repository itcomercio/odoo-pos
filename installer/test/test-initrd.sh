rm -fr initramfs

mkdir -p initramfs/{bin,sbin,etc,proc,sys,dev,lib64}
mkdir -p initramfs/{dev,proc,sys}
sudo mknod -m 600 initramfs/dev/console c 5 1
sudo mknod -m 666 initramfs/dev/null c 1 3
sudo mknod -m 666 initramfs/dev/zero c 1 5

# Copiar bash y dependencias
cp /bin/bash initramfs/bin/
ldd /bin/bash | grep "=>" | awk '{print $3}' | xargs -I {} cp {} initramfs/lib64/

# Crear script init
cat > initramfs/init << 'EOF'
#!/bin/bash
mount -t proc none /proc
mount -t sysfs none /sys
echo "Init script funcionando!"
sleep 10
EOF

chmod +x initramfs/init

# Empacar
cd initramfs
find . -print0 | cpio --null -ov --format=newc | gzip > ../initrd.img
