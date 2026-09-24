# Only interactive login shells: never pollute scp, sftp or remote commands.
case $- in
    *i*)
        if [ -t 1 ] && [ ! -e /etc/pico-motd.disabled ] && [ -x /usr/bin/pico-status ]; then
            /usr/bin/pico-status
        fi ;;
esac
