#!/bin/sh
# Install onto an already-running Alpine board, from this archive directory.
set -eu
[ "$(id -u)" = 0 ] || { echo 'Run as root on the board.' >&2; exit 1; }
[ -f /etc/alpine-release ] || { echo 'This installer is for Alpine Linux.' >&2; exit 1; }
cd "$(dirname "$0")"
for file in overlay/usr/sbin/pico-config overlay/usr/bin/pico-status overlay/usr/lib/pico-config/system.sh overlay/usr/lib/pico-config/storage.sh overlay/usr/lib/pico-config/users.sh overlay/etc/profile.d/90-pico-motd.sh; do
    [ -f "$file" ] || { echo "Missing $file" >&2; exit 1; }
done
apk add dialog tzdata iproute2 lsblk findmnt mount umount cifs-utils nfs-utils libgpiod openssh-keygen chrony chrony-openrc busybox-openrc usbutils
mkdir -p /usr/sbin /usr/bin /usr/lib/pico-config /etc/profile.d
cp overlay/usr/sbin/pico-config /usr/sbin/pico-config
cp overlay/usr/bin/pico-status /usr/bin/pico-status
cp overlay/usr/lib/pico-config/*.sh /usr/lib/pico-config/
cp overlay/etc/profile.d/90-pico-motd.sh /etc/profile.d/90-pico-motd.sh
chmod 755 /usr/sbin/pico-config /usr/bin/pico-status
chmod 644 /usr/lib/pico-config/*.sh /etc/profile.d/90-pico-motd.sh
echo 'Installed. Run pico-config. Login summary appears on your next interactive login.'
