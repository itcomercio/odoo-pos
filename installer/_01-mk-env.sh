#!/usr/bin/env bash

# Tested with:
# $ cat /etc/fedora-release
#   Fedora release 43 (Forty Three)

source include/functions.env

echo_note "WARNING" "#### Installing Development Tools ####"
echo_note "WARNING" "#### Needed root password for installing tools ####"
sudo dnf install @development-tools -y |& grep -v "is already installed"
echo_note "OK" "#### Packages installed! ####"

echo_note "WARNING" "#### Installing Dependency packages ####"
sudo dnf install -y -q \
    audit-libs-devel \
    libuuid-devel \
    isomd5sum-devel \
    glib2-devel \
    NetworkManager-libnm-devel \
    squashfs-tools \
    e2fsprogs-devel \
    popt-devel \
    libblkid-devel \
    libX11-devel \
    libnl3-devel \
    newt-devel \
    device-mapper-devel \
    python \
    python-devel \
    zlib-devel \
    net-tools \
    nfs-utils \
    strace \
    tree \
    vim \
    gdb \
    grub2-tools \
    parted-devel \
    python3-dialog \
    dhcp-client \
    policycoreutils \
    genisoimage \
    python3-pyparted \
    udisks2 \
    nasm \
    dbus-devel \
    xorriso |& grep -v "is already installed"

echo_note "OK" "#### All packages installed! ####"
