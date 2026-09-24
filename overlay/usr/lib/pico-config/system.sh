#!/bin/sh
# Alpine ash and POSIX-compatible shells with local variables.

need() {
    command -v "$1" >/dev/null 2>&1 && return 0
    msg "Missing command: $1. Install package: $2 (Packages menu)."
    return 1
}
run_view() {
    local result
    "$@" > "$work/result" 2>&1
    result=$?
    printf '\nExit status: %s\n' "$result" >> "$work/result"
    view "$work/result"
    return "$result"
}
token() {
    case "$1" in ''|[!a-zA-Z0-9]*|*[!a-zA-Z0-9_.+-]*) return 1 ;; esac
}
username_valid() {
    [ "${#1}" -le 32 ] || return 1
    case "$1" in ''|[!a-z_]*|*[!a-z0-9_-]*) return 1 ;; esac
}

packages() {
    local action name
    need apk apk-tools || return
    action=$(dialog --stdout --menu 'Packages (requires writable rootfs and Internet)' 18 76 8 \
        list 'Installed packages' search 'Search repository' info 'Package details' \
        add 'Install package' del 'Remove package' update 'Refresh indexes' upgrade 'Upgrade installed packages') || return
    case "$action" in
        list) run_view apk info; return ;;
        update) confirm 'Refresh APK indexes?' && run_view apk update; return ;;
        upgrade)
            run_view apk upgrade --simulate || return
            confirm 'Upgrade packages shown above? This does not upgrade the Rockchip kernel/firmware. Check free space first.' && run_view apk upgrade
            return ;;
    esac
    name=$(ask 'One package name (letters, numbers, + . _ -):') || return
    token "$name" || { msg 'Invalid package name.'; return; }
    case "$action" in
        search) run_view apk search "$name" ;;
        info) run_view apk info -a "$name" ;;
        add|del)
            if [ "$action" = del ]; then
                case "$name" in alpine-base|alpine-baselayout|apk-tools|busybox|musl|openrc|dialog|openssh*|bash)
                    msg 'Removing this core/access package is disabled in the menu.'; return ;;
                esac
            fi
            run_view apk "$action" --simulate "$name" || return
            confirm "$action $name and the dependencies shown above?" && run_view apk "$action" "$name" ;;
    esac
}

services() {
    local file service action level
    set --
    for file in /etc/init.d/*; do
        [ -x "$file" ] && [ -f "$file" ] || continue
        service=${file##*/}
        set -- "$@" "$service" 'OpenRC service'
    done
    [ "$#" -gt 0 ] || { msg 'No services found.'; return; }
    service=$(dialog --stdout --menu 'Services' 22 76 14 "$@") || return
    action=$(dialog --stdout --menu "$service" 19 72 8 \
        status 'Status' start 'Start now' stop 'Stop now' restart 'Restart now' \
        enable 'Enable in selected runlevel' disable 'Disable in selected runlevel' levels 'Show all runlevels') || return
    case "$action" in
        status) run_view rc-service "$service" status; return ;;
        levels) run_view rc-update show -v; return ;;
        enable|disable)
            level=$(dialog --stdout --menu 'Runlevel' 12 68 3 default 'Normal services' boot 'Early boot services' sysinit 'System initialization') || return ;;
    esac
    confirm "$action $service? Changes to networking, SSH or boot services can prevent access/boot." || return
    case "$action" in
        enable) run_view rc-update add "$service" "$level" ;;
        disable) run_view rc-update del "$service" "$level" ;;
        *) run_view rc-service "$service" "$action" ;;
    esac
}

journal() {
    local action
    action=$(dialog --stdout --menu 'Logs' 17 72 6 \
        kernel 'Kernel ring buffer' system 'Last 300 system messages' boot 'OpenRC boot log' \
        process 'Processes' logger 'Start/enable syslog via Services') || return
    case "$action" in
        kernel) dmesg | tail -n 300 > "$work/log"; view "$work/log" ;;
        system)
            if [ -r /var/log/messages ]; then run_view tail -n 300 /var/log/messages
            elif command -v logread >/dev/null 2>&1; then run_view logread
            else msg 'No syslog available. Enable syslog in Services. Past messages cannot be recovered.'; fi ;;
        boot) [ ! -r /var/log/rc.log ] || { run_view tail -n 300 /var/log/rc.log; return; }
            msg 'No /var/log/rc.log. OpenRC boot logging may be disabled.' ;;
        process) run_view ps ;;
        logger) services ;;
    esac
}

devices() {
    local action
    action=$(dialog --stdout --menu 'Devices' 18 72 8 usb 'USB devices' block 'Block devices' \
        net 'Network interfaces' gpio 'GPIO controllers/lines' modules 'Kernel modules' \
        buses 'I2C / SPI / serial / video devices' fs 'Supported filesystems') || return
    case "$action" in
        usb) need lsusb usbutils && run_view lsusb ;;
        block)
            { command -v lsblk >/dev/null && lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
              [ ! -r /proc/mtd ] || { printf '\nFlash (MTD):\n'; cat /proc/mtd; }
              for file in /sys/class/ubi/ubi*; do [ ! -d "$file" ] || printf '%s\n' "$file"; done
            } > "$work/block" 2>&1
            view "$work/block" ;;
        net) run_view ip -s link ;;
        gpio) need gpioinfo libgpiod && run_view gpioinfo ;;
        modules) run_view lsmod ;;
        fs) run_view cat /proc/filesystems ;;
        buses)
            { for file in /dev/i2c-* /dev/spidev* /dev/ttyS* /dev/ttyFIQ* /dev/ttyUSB* /dev/ttyACM* /dev/video*; do
                [ ! -e "$file" ] || ls -l "$file"
              done; } > "$work/devices"
            view "$work/devices" ;;
    esac
}

internet() {
    local action target
    action=$(dialog --stdout --menu 'Internet / network' 19 76 8 address 'Ethernet / USB addressing' dns 'DNS server' \
        routes 'Addresses and routing table' ping 'Ping host' lookup 'DNS lookup' \
        restore 'Restore previous address configuration' repos 'View APK repositories') || return
    case "$action" in
        address) network ;;
        dns) dns ;;
        restore) restore_network ;;
        routes) { ip addr; ip route; cat /etc/resolv.conf; } > "$work/net" 2>&1; view "$work/net" ;;
        repos) run_view cat /etc/apk/repositories ;;
        ping|lookup)
            target=$(ask 'Hostname or IPv4 address:' 'alpinelinux.org') || return
            case "$target" in ''|[!a-zA-Z0-9]*|*[!a-zA-Z0-9.-]*) msg 'Invalid host.'; return ;; esac
            if [ "$action" = ping ]; then run_view ping -c 3 -W 3 "$target"
            else need timeout coreutils && run_view timeout 10 nslookup "$target"; fi ;;
    esac
}

time_menu() {
    local action value
    action=$(dialog --stdout --menu 'Date and time' 18 76 7 status 'Time / NTP status' timezone 'Timezone' \
        manual 'Set date/time manually' sync 'Apply current chrony correction now' server 'Set NTP server' \
        service 'Enable/start chronyd via Services') || return
    case "$action" in
        status) { date; command -v chronyc >/dev/null && { chronyc tracking; chronyc sources; }; } > "$work/time" 2>&1; view "$work/time" ;;
        timezone) timezone ;;
        service) services ;;
        sync) need chronyc chrony || return
            confirm 'Apply chrony clock correction now? chronyd must be running and have a valid time source.' && run_view chronyc makestep ;;
        manual)
            value=$(ask 'Local time: YYYY-MM-DD HH:MM:SS' "$(date '+%Y-%m-%d %H:%M:%S')") || return
            printf '%s\n' "$value" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' || { msg 'Invalid date format.'; return; }
            confirm "Set time to $value? Running NTP may change it again." && run_view date -s "$value" ;;
        server)
            need chronyd chrony || return
            value=$(ask 'NTP server hostname:' 'pool.ntp.org') || return
            case "$value" in ''|[!a-zA-Z0-9]*|*[!a-zA-Z0-9.-]*) msg 'Invalid server.'; return ;; esac
            [ -f /etc/chrony/chrony.conf ] || { msg 'Expected /etc/chrony/chrony.conf not found.'; return; }
            awk '$1!="pool" && $1!="server" && $1!="peer" {print}' /etc/chrony/chrony.conf > "$work/chrony"
            printf '\nserver %s iburst\n' "$value" >> "$work/chrony"
            confirm "Replace configured NTP sources with $value?" || return
            save_file /etc/chrony/chrony.conf "$work/chrony" || { msg 'Save failed.'; return; }
            msg 'Saved. Restart chronyd in Services to apply. Sources loaded from included files remain unchanged.' ;;
    esac
}

gpio_menu() {
    local action chip file line value pid result version
    need gpioinfo libgpiod || return
    set --
    for file in /dev/gpiochip*; do [ -c "$file" ] && set -- "$@" "${file##*/}" 'GPIO controller'; done
    [ "$#" -gt 0 ] || { msg 'No /dev/gpiochip devices. Kernel GPIO character-device support is required.'; return; }
    chip=$(dialog --stdout --menu 'GPIO controller (chip offsets, NOT header pin numbers)' 18 76 8 "$@") || return
    action=$(dialog --stdout --menu 'GPIO action' 14 76 4 info 'List lines and consumers' read 'Read a free line as input' set 'Hold a free line LOW/HIGH until dismissed') || return
    version=1
    gpioinfo --help 2>&1 | grep -q -- '--chip' && version=2
    if [ "$action" = info ]; then
        if [ "$version" = 2 ]; then run_view gpioinfo -c "$chip"; else run_view gpioinfo "$chip"; fi
        return
    fi
    line=$(ask 'Line offset within this chip (check gpioinfo and board pinout):') || return
    case "$line" in ''|*[!0-9]*) msg 'Invalid offset.'; return ;; esac
    confirm 'Confirm the pin mapping and wiring. The menu does not change pin multiplexing. Never use power/flash/UART pins or lines owned by a driver.' || return
    if [ "$action" = read ]; then
        if [ "$version" = 2 ]; then run_view gpioget -c "$chip" "$line"; else run_view gpioget "$chip" "$line"; fi
    else
        need gpioset libgpiod || return
        value=$(dialog --stdout --menu 'Output level' 11 65 2 0 LOW 1 HIGH) || return
        # Run a holder process only while this dialog is open. Subshell traps
        # release our own line on cancellation/disconnect, never unrelated GPIO.
        (
            if [ "$version" = 2 ]; then gpioset -c "$chip" "$line=$value" > "$work/gpio" 2>&1 &
            else gpioset --mode=signal "$chip" "$line=$value" > "$work/gpio" 2>&1 & fi
            pid=$!
            trap 'kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null' EXIT
            trap 'exit 1' HUP INT TERM
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                msg "Holding $chip line $line at $value. Close this dialog to release it. After release the level is NOT guaranteed."
            else view "$work/gpio"; fi
        )
    fi
}

# Replaces the small first-version menu after all modules are sourced.
main() {
    [ "$(id -u)" = 0 ] || { echo 'Run pico-config as root.' >&2; return 1; }
    [ -t 0 ] && [ -t 1 ] || { echo 'Interactive terminal required (ssh -t).' >&2; return 1; }
    command -v dialog >/dev/null || { echo 'Install dialog first.' >&2; return 1; }
    umask 077
    work=$(mktemp -d) || return 1
    trap 'rm -rf "$work"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    while choice=$(dialog --stdout --title 'Luckfox Pico Config 2' --menu 'System administration' 24 78 16 \
        info 'System summary / MOTD' packages 'Packages' backup 'Configuration backup / restore' \
        mounts 'Partitions / NFS / SMB' logs 'Logs' services 'OpenRC services' users 'Users / SSH' \
        gpio 'GPIO' internet 'Internet / network' time 'Date / timezone / NTP' devices 'Devices' \
        hostname 'Hostname' motd 'Enable/disable login summary' reboot 'Reboot' exit 'Exit'); do
        case "$choice" in
            info) run_view /usr/bin/pico-status ;;
            packages) packages ;;
            backup) backup_menu ;;
            mounts) mounts_menu ;;
            logs) journal ;;
            services) services ;;
            users) users_menu ;;
            gpio) gpio_menu ;;
            internet) internet ;;
            time) time_menu ;;
            devices) devices ;;
            hostname) set_hostname ;;
            motd)
                if [ -f /etc/pico-motd.disabled ]; then rm -f /etc/pico-motd.disabled; msg 'Login summary enabled.'
                else : > /etc/pico-motd.disabled; msg 'Login summary disabled.'; fi ;;
            reboot) if confirm 'Reboot now?'; then sync; reboot; return; fi ;;
            exit) break ;;
        esac
    done
    clear
}
