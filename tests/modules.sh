#!/bin/sh
set -eu
PICO_CONFIG_LIBRARY_ONLY=1
export PICO_CONFIG_LIBRARY_ONLY
. ./overlay/usr/sbin/pico-config
. ./overlay/usr/lib/pico-config/storage.sh
. ./overlay/usr/lib/pico-config/system.sh
. ./overlay/usr/lib/pico-config/users.sh

reject() { if "$@"; then printf 'Unexpected acceptance: %s\n' "$*"; exit 1; fi; }
token nfs-utils
token libstdc++
reject token --root
reject token 'pkg;reboot'
reject token 'pkg other'
username_valid pico_user-1
reject username_valid 'user/../../root'
reject username_valid --system
mount_name_valid nas-1
reject mount_name_valid '../etc'
reject mount_name_valid 'a b'
share_valid '//nas.example/share'
share_valid '192.168.1.2:/exports/disk'
reject share_valid '//host/share,password=secret'
reject share_valid 'host:/share with spaces'
backup_allowed etc/network/interfaces
reject backup_allowed /etc/network/interfaces
reject backup_allowed etc/../root/.ssh/authorized_keys
reject backup_allowed etc/shadow
reject backup_allowed etc/fstab
echo 'Input and backup allowlist tests passed'

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
work="$test_dir"
# UI/command mocks: exercise action dispatch without invoking APK or changing host.
need() { return 0; }
dialog() { printf '%s\n' "$test_action"; }
ask() { printf '%s\n' "$test_name"; }
msg() { printf '%s\n' "$1" >> "$test_dir/messages"; }
confirm() { return "$test_confirm"; }
run_view() { printf '%s\n' "$*" >> "$test_dir/calls"; return 0; }
test_action=add test_name=cifs-utils test_confirm=0
packages
grep -qx 'apk add --simulate cifs-utils' "$test_dir/calls"
grep -qx 'apk add cifs-utils' "$test_dir/calls"
: > "$test_dir/calls"
test_action=add test_name=libgpiod test_confirm=1
packages || :
grep -qx 'apk add --simulate libgpiod' "$test_dir/calls"
if grep -qx 'apk add libgpiod' "$test_dir/calls"; then echo 'Cancelled install executed'; exit 1; fi
: > "$test_dir/calls"
test_action=del test_name=busybox test_confirm=0
packages
[ ! -s "$test_dir/calls" ]
test_action=add test_name='--root=/tmp'
packages
[ ! -s "$test_dir/calls" ]
echo 'Package action/cancellation tests passed'

# Run the status formatter against known telemetry without probing a real board.
mkdir -p "$test_dir/proc" "$test_dir/etc" "$test_dir/sys/class/thermal/thermal_zone0"
printf '90061 0\n' > "$test_dir/proc/uptime"
printf '0.12 0.34 0.56 1/25 200\n' > "$test_dir/proc/loadavg"
printf 'MemTotal: 65536 kB\nMemAvailable: 32768 kB\nMemFree: 8192 kB\nSwapTotal: 0 kB\n' > "$test_dir/proc/meminfo"
printf '3.test\n' > "$test_dir/etc/alpine-release"
printf 'cpu-thermal\n' > "$test_dir/sys/class/thermal/thermal_zone0/type"
printf '42500\n' > "$test_dir/sys/class/thermal/thermal_zone0/temp"
PICO_STATUS_PROC_ROOT="$test_dir/proc" PICO_STATUS_SYS_ROOT="$test_dir/sys" PICO_STATUS_ETC_ROOT="$test_dir/etc" \
    sh ./overlay/usr/bin/pico-status > "$test_dir/status" 2>/dev/null
grep -q '1d 1h 1m' "$test_dir/status"
grep -q '64.0 MiB total, 32.0 MiB available' "$test_dir/status"
grep -q '0.12 / 0.34 / 0.56' "$test_dir/status"
grep -q 'Temperature (cpu-thermal): 42.5 C' "$test_dir/status"
echo 'MOTD telemetry tests passed'

# Noninteractive profile sourcing must be silent (scp/automation compatibility).
sh -c '. ./overlay/etc/profile.d/90-pico-motd.sh' > "$test_dir/profile"
[ ! -s "$test_dir/profile" ]
echo 'Noninteractive login test passed'
