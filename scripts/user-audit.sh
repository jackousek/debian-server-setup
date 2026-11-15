
#!/usr/bin/env bash
set -euo pipefail

# Debian user security audit
# Run as root.
#
# root      - console recovery, no SSH login
# itadmin   - SSH public key + sudo
# backupsvc - SSH public key for backups
# chinook   - legacy UID 0 account, disable login

[[ $EUID -eq 0 ]] || {
    echo "ERROR: Run as root."
    exit 1
}

audit() {
    echo "=== UID 0 ACCOUNTS ==="
    getent passwd | awk -F: '$3 == 0 {
        print $1, "UID=" $3, "SHELL=" $7
    }'

    echo
    echo "=== ACCOUNTS WITH USABLE PASSWORDS ==="
    while IFS=: read -r user rest; do
        status=$(passwd -S "$user" 2>/dev/null |
                 awk '{print $2}')

        if [[ "$status" == "P" ]]; then
            echo "$user"
        fi
    done < <(getent passwd)

    echo
    echo "=== ACCOUNTS WITH LOGIN SHELLS ==="
    getent passwd | awk -F: '
        $7 !~ /(nologin|false)$/ {
            print $1, "UID=" $3, "SHELL=" $7
        }'

    echo
    echo "=== SSH AUTHORIZED KEYS ==="
    while IFS=: read -r user x uid gid info home shell; do
        if [[ -s "$home/.ssh/authorized_keys" ]]; then
            echo "$user: $home/.ssh/authorized_keys"
        fi
    done < <(getent passwd)

    echo
    echo "=== SUDO MEMBERS ==="
    getent group sudo || true

    echo
    echo "=== IMPORTANT ACCOUNTS ==="

    for user in root itadmin backupsvc chinook; do
        echo
        echo "--- $user ---"

        if getent passwd "$user" >/dev/null; then
            getent passwd "$user"
            passwd -S "$user"
            chage -l "$user" |
                grep -E 'Account expires|Password expires' || true
        else
            echo "Account does not exist."
        fi
    done

    echo
    echo "=== EFFECTIVE SSH POLICY ==="
    /usr/sbin/sshd -t

    for user in root itadmin backupsvc chinook; do
        if getent passwd "$user" >/dev/null; then
            echo "--- $user ---"
            /usr/sbin/sshd -T \
                -C user="$user",host=localhost,addr=127.0.0.1 |
                grep -E '^(permitrootlogin|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|authenticationmethods) '
        fi
    done
}

disable_chinook() {
    if ! getent passwd chinook >/dev/null; then
        echo "chinook does not exist."
        exit 0
    fi

    echo "=== DISABLE CHINOOK ==="
    getent passwd chinook
    passwd -S chinook

    echo
    echo "WARNING: chinook may have UID 0."
    echo "Verify no services, cron jobs or backups depend on it."
    echo "Existing sessions and processes will remain active."
    echo "backupsvc and itadmin will not be modified."

    read -r -p "Type YES to disable chinook: " answer
    [[ "$answer" == "YES" ]] || exit 1

    usermod --lock chinook
    usermod --expiredate 1 chinook
    usermod --shell /usr/sbin/nologin chinook

    echo
    echo "=== CHINOOK STATUS ==="
    getent passwd chinook
    passwd -S chinook
    chage -l chinook | grep 'Account expires'

    echo
    echo "chinook account disabled for normal login."
}

case "${1:-}" in
    --status)
        audit
        ;;
    --disable-chinook)
        disable_chinook
        ;;
    *)
        echo "Usage:"
        echo "  $0 --status"
        echo "  $0 --disable-chinook"
        exit 2
        ;;
esac


