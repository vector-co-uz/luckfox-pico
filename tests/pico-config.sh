#!/bin/sh
set -eu
PICO_CONFIG_LIBRARY_ONLY=1
export PICO_CONFIG_LIBRARY_ONLY
. ./overlay/usr/sbin/pico-config

for ip in 0.0.0.0 10.10.10.70 172.32.0.93 255.255.255.255; do valid_ipv4 "$ip"; done
for ip in '' 1.2.3 256.1.2.3 1.2.3.4.5 '1.2.3.x' '1.2.3.4;reboot'; do
    if valid_ipv4 "$ip"; then echo "Accepted invalid IP: $ip"; exit 1; fi
done
valid_hostname pico-mini-b
for host in '' '-pico' 'pico-' 'pico mini' 'pico;reboot'; do
    if valid_hostname "$host"; then echo "Accepted invalid hostname: $host"; exit 1; fi
done
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cat > "$test_dir/interfaces" <<'EOF'
auto lo
iface lo inet loopback
auto eth0 usb0
iface eth0 inet static
    address 10.10.10.70
    netmask 255.255.255.0
    gateway 10.10.10.1
iface usb0 inet static
    address 172.32.0.93
    netmask 255.255.255.0
EOF
simple_network "$test_dir/interfaces"
render_network "$test_dir/interfaces" eth0 dhcp '' '' '' > "$test_dir/new"
grep -q 'address 172.32.0.93' "$test_dir/new"
grep -q '^auto usb0$' "$test_dir/new"
grep -q '^iface eth0 inet dhcp$' "$test_dir/new"
if grep -q '10.10.10.' "$test_dir/new"; then echo 'Stale Ethernet settings'; exit 1; fi
render_network "$test_dir/new" usb0 static 192.168.7.2 255.255.255.0 '' > "$test_dir/static"
grep -q '^iface eth0 inet dhcp$' "$test_dir/static"
grep -q 'address 192.168.7.2' "$test_dir/static"
if grep -q '172.32.0.93' "$test_dir/static"; then exit 1; fi
echo 'source /etc/network/interfaces.d/*' >> "$test_dir/interfaces"
if simple_network "$test_dir/interfaces"; then echo 'Accepted advanced layout'; exit 1; fi
echo 'Validation and network rendering tests passed'
[ "${1:-}" != --network-only ] || exit 0
printf 'old\n' > "$test_dir/config"
printf 'new\n' > "$test_dir/input"
save_file "$test_dir/config" "$test_dir/input"
grep -qx old "$test_dir/config.pico-original"
grep -qx old "$test_dir/config.pico-previous"
grep -qx new "$test_dir/config"
printf 'third\n' > "$test_dir/input"
save_file "$test_dir/config" "$test_dir/input"
grep -qx old "$test_dir/config.pico-original"
grep -qx new "$test_dir/config.pico-previous"
echo 'pico-config tests passed'
