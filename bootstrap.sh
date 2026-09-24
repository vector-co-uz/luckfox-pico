#!/bin/sh
set -e

# Install base
apk update
apk add openrc
rc-update add devfs boot
rc-update add procfs boot
rc-update add sysfs boot
rc-update add networking default
rc-update add local default

# Install TTY
apk add agetty

# Setting up shell
apk add shadow
apk add bash bash-completion
chsh -s /bin/bash
echo -e "luckfox\nluckfox" | passwd
apk del -r shadow

# Install SSH
apk add openssh
rc-update add sshd default

# Extra stuff
apk add mtd-utils-ubi
apk add bottom
apk add wget
apk add nano
apk add mc
apk add chrony
apk add usbutils
apk add dialog tzdata
apk add iproute2 lsblk findmnt mount umount cifs-utils nfs-utils libgpiod openssh-keygen chrony-openrc busybox-openrc

# Clear apk cache
rm -rf /var/cache/apk/*

# Packaging rootfs
for d in bin etc lib sbin usr var; do cp -a "$d" /extrootfs/; done
for dir in dev proc root run sys var oem userdata; do mkdir -p /extrootfs/${dir}; done
mkdir -p /extrootfs/var/empty
chown root:root /extrootfs/var/empty
chmod 755 /extrootfs/var/empty
mkdir -p /extrootfs/tmp
chmod 1777 /extrootfs/tmp
