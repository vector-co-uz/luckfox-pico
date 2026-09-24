#!/bin/sh

backup_allowed() {
    case "$1" in
        etc/hostname|etc/hosts|etc/network/interfaces|etc/resolv.conf|etc/timezone|etc/localtime|etc/chrony/chrony.conf|etc/ssh/sshd_config|etc/ssh/sshd_config.d/05-pico-config.conf|etc/apk/world|etc/apk/repositories) return 0 ;;
        *) return 1 ;;
    esac
}

backup_menu() {
    local action archive item dest size stage entry
    action=$(dialog --stdout --menu 'Configuration backup (not a disk image)' 15 76 5 \
        create 'Create backup of network/time/SSH/APK configuration' inspect 'List archive contents' restore 'Restore one configuration file') || return
    archive=$(ask 'Absolute archive path (.tar.gz); use a mounted disk if needed:' "/root/pico-settings-$(date +%Y%m%d-%H%M%S).tar.gz") || return
    case "$archive" in /*.tar.gz) ;; *) msg 'Use an absolute .tar.gz path.'; return ;; esac
    if [ "$action" = create ]; then
        [ ! -e "$archive" ] && [ ! -L "$archive" ] || { msg 'File already exists. Choose another name.'; return; }
        set --
        for item in etc/hostname etc/hosts etc/network/interfaces etc/resolv.conf etc/timezone etc/localtime etc/chrony/chrony.conf etc/ssh/sshd_config etc/ssh/sshd_config.d/05-pico-config.conf etc/apk/world etc/apk/repositories; do
            [ -f "/$item" ] && [ ! -L "/$item" ] && set -- "$@" "$item"
        done
        [ "$#" -gt 0 ] || { msg 'No configuration files found.'; return; }
        confirm 'Create a private archive? Contains selected configuration only, not packages, passwords, SSH keys, SMB credentials or disk data. Symlinks are skipped.' || return
        # Exclusive creation: never follow or replace an existing destination.
        if (set -C; umask 077; tar -czf - -C / "$@" > "$archive") 2> "$work/backup-error"; then
            msg "Saved: $archive. Copy it off the board."
        else msg "Backup failed. An incomplete archive may exist at $archive."; view "$work/backup-error"; fi
        return
    fi
    [ -f "$archive" ] || { msg 'Archive not found.'; return; }
    if [ "$action" = inspect ]; then run_view tar -tzf "$archive"; return; fi
    tar -tzf "$archive" > "$work/members" 2> "$work/backup-error" || { view "$work/backup-error"; return; }
    set --
    while IFS= read -r item; do
        backup_allowed "$item" && set -- "$@" "$item" 'Restore file'
    done < "$work/members"
    [ "$#" -gt 0 ] || { msg 'No supported configuration files in archive.'; return; }
    item=$(dialog --stdout --menu 'Restore a file (services are not restarted)' 22 78 12 "$@") || return
    backup_allowed "$item" || return
    # Only one regular-file member is accepted; no archive extraction to /.
    tar -tvzf "$archive" "$item" > "$work/member-detail" 2>/dev/null || return
    [ "$(wc -l < "$work/member-detail" | tr -d ' ')" = 1 ] || { msg 'Duplicate/ambiguous archive entry.'; return; }
    case "$(head -c 1 "$work/member-detail")" in -) ;; *) msg 'Only regular files can be restored.'; return ;; esac
    stage="$work/restored"
    # Bound output before writing a possibly untrusted archive member into RAM.
    tar -xOzf "$archive" "$item" | head -c 1048577 > "$stage"
    size=$(wc -c < "$stage")
    [ "$size" -le 1048576 ] || { msg 'Configuration file exceeds 1 MiB.'; return; }
    dest="/$item"
    [ ! -L "$dest" ] || { msg 'Destination is a symlink; restore manually.'; return; }
    [ -d "${dest%/*}" ] || { msg 'Destination directory is missing.'; return; }
    confirm "Restore $dest? Previous version is backed up. SSH/network changes can affect your next login or reboot. APK world restore does not install packages." || return
    save_file "$dest" "$stage" && msg 'Restored. Restart the relevant service or reboot to apply.' || msg 'Restore failed.'
}

mount_name_valid() {
    [ "${#1}" -le 40 ] || return 1
    case "$1" in ''|[!a-zA-Z0-9]*|*[!a-zA-Z0-9_-]*) return 1 ;; esac
}
share_valid() {
    # No whitespace/commas/control characters: can be represented in fstab.
    case "$1" in ''|*[!a-zA-Z0-9_./:@+-]*) return 1 ;; esac
}
mounts_menu() {
    local action type source name target access options user pass creds result node
    action=$(dialog --stdout --menu 'Storage / network shares' 18 76 7 \
        list 'Mounted filesystems / space' local 'Mount a local partition' nfs 'Mount NFS share' \
        smb 'Mount SMB share (SMB3)' saved 'Mount saved entry' unmount 'Unmount a Pico mount' fstab 'View fstab') || return
    case "$action" in
        list) { df -h; cat /proc/mounts; } > "$work/mounts"; view "$work/mounts"; return ;;
        fstab) run_view cat /etc/fstab; return ;;
        saved|unmount)
            name=$(ask 'Pico mount name (target /mnt/pico-NAME):') || return
            mount_name_valid "$name" || { msg 'Invalid mount name.'; return; }
            target="/mnt/pico-$name"
            [ ! -L "$target" ] || { msg 'Symlink mountpoint rejected.'; return; }
            if [ "$action" = saved ]; then
                awk -v t="$target" '$2==t {found=1} END {exit !found}' /etc/fstab || { msg 'No saved entry.'; return; }
                confirm "Mount saved $target?" && run_view mount "$target"
            else confirm "Unmount $target? Busy mounts will not be forced." && run_view umount "$target"; fi
            return ;;
    esac
    need mount util-linux || return
    case "$action" in
        local)
            need lsblk lsblk || return
            run_view lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
            source=$(ask 'Block device path, e.g. /dev/mmcblk0p1:') || return
            case "$source" in /dev/*) ;; *) msg 'Use a /dev block device.'; return ;; esac
            share_valid "$source" && [ -b "$source" ] || { msg 'Invalid block device.'; return; }
            need findmnt findmnt || return
            if findmnt -rn -S "$source" > /dev/null; then msg 'This device is already mounted.'; return; fi
            type=$(dialog --stdout --menu 'Filesystem' 15 68 5 ext4 ext4 ext3 ext3 ext2 ext2 vfat FAT exfat exFAT) || return ;;
        nfs)
            need mount.nfs nfs-utils || return
            type=nfs
            source=$(ask 'NFS source: server:/export/path') || return
            share_valid "$source" || { msg 'Invalid NFS source.'; return; }
            case "$source" in ?*:/*) ;; *) msg 'Expected server:/export/path.'; return ;; esac ;;
        smb)
            need mount.cifs cifs-utils || return
            type=cifs
            source=$(ask 'SMB source: //server/share') || return
            share_valid "$source" || { msg 'Invalid SMB source.'; return; }
            case "$source" in //?*/?*) ;; *) msg 'Expected //server/share.'; return ;; esac ;;
    esac
    name=$(ask 'Mount name (letters/digits/_/-), creates /mnt/pico-NAME:') || return
    mount_name_valid "$name" || { msg 'Invalid name.'; return; }
    target="/mnt/pico-$name"
    [ ! -L "$target" ] || { msg 'Symlink mountpoint rejected.'; return; }
    need findmnt findmnt || return
    if findmnt -rn -M "$target" >/dev/null; then msg 'Target is already mounted.'; return; fi
    if [ -d "$target" ] && [ -n "$(ls -A "$target")" ]; then msg 'Target directory must be empty.'; return; fi
    access=$(dialog --stdout --menu 'Access mode' 12 72 2 ro 'Read-only (default)' rw 'Read/write') || return
    options="$access,nosuid,nodev"
    case "$type" in
        nfs) options="$options,vers=4,_netdev" ;;
        cifs)
            user=$(ask 'SMB username (DOMAIN/user is supported):') || return
            [ -n "$user" ] || { msg 'Username is required.'; return; }
            case "$user" in *'
'*) msg 'Username must be one line.'; return ;; esac
            pass=$(dialog --stdout --insecure --passwordbox 'SMB password (stored privately if entry is saved)' 10 76) || return
            case "$pass" in *'
'*) unset pass; msg 'Password must be one line.'; return ;; esac
            creds="$work/smb-credentials"
            printf 'username=%s\npassword=%s\n' "$user" "$pass" > "$creds"
            unset pass
            chmod 600 "$creds"
            options="$options,vers=3.0,_netdev,credentials=$creds" ;;
    esac
    confirm "Mount $source at $target ($access)? Kernel support for $type is required." || return
    mkdir -p "$target" || { msg 'Cannot create mountpoint.'; return; }
    # mount.cifs receives only a credentials FILE path, never the password.
    if ! run_view mount -t "$type" -o "$options" "$source" "$target"; then
        [ -z "${creds:-}" ] || rm -f "$creds"
        return
    fi
    confirm 'Save entry in fstab for manual mounting after reboot? It will use noauto, so a missing server will not block boot.' || return
    if awk -v t="$target" '$2==t {found=1} END {exit !found}' /etc/fstab 2>/dev/null; then
        msg 'An fstab entry already exists. Mounted now; existing entry was not changed.'; return
    fi
    if [ "$type" = cifs ]; then
        mkdir -p /etc/pico-config/credentials || return
        chmod 700 /etc/pico-config /etc/pico-config/credentials
        node="/etc/pico-config/credentials/$name"
        [ ! -e "$node" ] && [ ! -L "$node" ] || { msg 'Credentials file already exists. Entry was not saved.'; return; }
        (set -C; umask 077; cat "$creds" > "$node") || return
        options="$access,nosuid,nodev,vers=3.0,_netdev,credentials=$node"
    fi
    cat /etc/fstab > "$work/fstab" 2>/dev/null || : > "$work/fstab"
    printf '\n%s %s %s noauto,%s 0 0\n' "$source" "$target" "$type" "$options" >> "$work/fstab"
    save_file /etc/fstab "$work/fstab" && msg 'Saved. Use Mount saved entry after reboot.' || msg 'Mounted, but saving fstab failed.'
}
