#!/bin/sh

choose_user() {
    local name uid
    set --
    while IFS=: read -r name _ uid _; do
        [ "$name" = root ] || { [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ]; } || continue
        set -- "$@" "$name" "UID $uid"
    done < /etc/passwd
    dialog --stdout --menu 'User account' 20 72 12 "$@"
}

install_public_key() {
    local user record home uid gid key keydir keyfile
    user=$1
    record=$(awk -F: -v u="$user" '$1==u {print $3 ":" $4 ":" $6}' /etc/passwd)
    IFS=: read -r uid gid home <<EOF
$record
EOF
    case "$home" in /*) ;; *) msg 'Invalid home directory.'; return ;; esac
    [ -d "$home" ] && [ ! -L "$home" ] || { msg 'Missing/symlink home directory. Manage its keys manually.'; return; }
    key=$(ask 'Paste one OpenSSH public key (never a private key):') || return
    case "$key" in ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *) ;; *) msg 'Expected a public key.'; return ;; esac
    case "$key" in *'
'*) msg 'Use one key line.'; return ;; esac
    printf '%s\n' "$key" > "$work/public-key"
    need ssh-keygen openssh-keygen || return
    ssh-keygen -l -f "$work/public-key" > "$work/key-info" 2>&1 || { view "$work/key-info"; return; }
    view "$work/key-info"
    confirm "Append this public key to $user?" || return
    keydir="$home/.ssh"
    keyfile="$keydir/authorized_keys"
    [ ! -L "$keydir" ] && [ ! -L "$keyfile" ] || { msg 'Symlink key directory/file rejected.'; return; }
    mkdir -p "$keydir" && chmod 700 "$keydir" && chown "$uid:$gid" "$keydir" || { msg 'Cannot prepare .ssh.'; return; }
    if [ -f "$keyfile" ]; then
        cp -p "$keyfile" "$keydir/authorized_keys.pico-previous" || return
        chmod 600 "$keydir/authorized_keys.pico-previous"
        cat "$keyfile" > "$work/authorized_keys" || return
    else : > "$work/authorized_keys"; fi
    if ! grep -Fqx "$key" "$work/authorized_keys"; then printf '\n%s\n' "$key" >> "$work/authorized_keys"; fi
    # A temporary file in the same directory preserves atomic replacement.
    local staged
    staged=$(mktemp "$keydir/.pico-key.XXXXXX") || return
    if cat "$work/authorized_keys" > "$staged" && chmod 600 "$staged" && chown "$uid:$gid" "$staged" && mv "$staged" "$keyfile"; then
        msg 'Public key installed. Test a second SSH session before disabling password login.'
    else rm -f "$staged"; msg 'Key installation failed.'; fi
}

ssh_settings() {
    local action value file existed effective
    need sshd openssh-server || return
    action=$(dialog --stdout --menu 'SSH server' 17 76 6 status 'Effective configuration' check 'Validate configuration' \
        key 'Add public key to account' password 'Enable password login' keyonly 'Disable password login' service 'Manage SSH service') || return
    case "$action" in
        status) run_view sshd -T; return ;;
        check) run_view sshd -t; return ;;
        key) local user; user=$(choose_user) || return; install_public_key "$user"; return ;;
        service) services; return ;;
        password) value=yes ;;
        keyonly)
            confirm 'Have you verified a second SSH login using a key? Password login will be disabled. Existing sessions stay open.' || return
            value=no ;;
    esac
    file=/etc/ssh/sshd_config.d/05-pico-config.conf
    [ ! -L "$file" ] || { msg 'Symlink configuration rejected.'; return; }
    mkdir -p /etc/ssh/sshd_config.d || return
    existed=0
    if [ -f "$file" ]; then cp -p "$file" "$work/ssh-before" || return; existed=1; fi
    printf '# Managed by pico-config\nPasswordAuthentication %s\nKbdInteractiveAuthentication no\n' "$value" > "$work/sshd"
    confirm "Set PasswordAuthentication $value? Root login policy is unchanged." || return
    save_file "$file" "$work/sshd" || { msg 'Could not save.'; return; }
    if sshd -t > "$work/ssh-result" 2>&1 && sshd -T > "$work/ssh-effective" 2>> "$work/ssh-result" &&
        grep -qx "passwordauthentication $value" "$work/ssh-effective" && grep -qx 'kbdinteractiveauthentication no' "$work/ssh-effective"; then
        if run_view rc-service sshd reload; then msg 'SSH configuration applied. Check a second connection.'
        else msg 'Saved and validated, but reload failed. Check SSH service before restarting.'; fi
    else
        if [ "$existed" = 1 ]; then cp -p "$work/ssh-before" "$file"; else rm -f "$file"; fi
        msg 'Configuration failed validation or was overridden by another setting. Previous file restored; SSH was not reloaded.'
        view "$work/ssh-result"
    fi
}

users_menu() {
    local action user shell
    action=$(dialog --stdout --menu 'Users / SSH' 19 76 8 list 'List accounts' add 'Create user' password 'Change password' \
        lock 'Lock password login (keys may still work)' unlock 'Unlock password login' delete 'Delete user (keep home files)' ssh 'SSH settings / public keys') || return
    case "$action" in
        list) run_view awk -F: '{printf "%-20s UID=%-6s home=%-24s shell=%s\n",$1,$3,$6,$7}' /etc/passwd; return ;;
        ssh) ssh_settings; return ;;
        add)
            user=$(ask 'New username (lowercase letters, digits, _ and -):') || return
            username_valid "$user" || { msg 'Invalid username.'; return; }
            if id "$user" >/dev/null 2>&1; then msg 'Account already exists.'; return; fi
            confirm "Create $user with /bin/ash and a home directory?" || return
            run_view adduser -D -s /bin/ash "$user" || return
            clear; passwd "$user"; msg 'Account created. If setting a password failed, use Change password or install an SSH key.'
            return ;;
    esac
    user=$(choose_user) || return
    case "$action" in
        password) clear; passwd "$user"; msg "Password command exit status: $?" ;;
        lock|unlock|delete)
            [ "$user" != root ] || { msg 'Root lock/removal is disabled in this menu.'; return; }
            confirm "$action account $user? Deleting an account keeps home files. Locking only affects password authentication." || return
            case "$action" in
                lock) run_view passwd -l "$user" ;;
                unlock) run_view passwd -u "$user" ;;
                delete) run_view deluser "$user" ;;
            esac ;;
    esac
}
