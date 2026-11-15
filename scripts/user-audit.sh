
#!/usr/bin/env bash
set -euo pipefail

# Debian user audit and legacy account cleanup.
# Run as root.
#
# root      - console recovery
# itadmin   - SSH public key + sudo
# backupsvc - SSH public key for backups (do not modify)
# chinook   - legacy account to disable

[[ $EUID -eq 0 ]] || {
    echo "ERROR: Run as root."
    exit 1
}

show_chinook() {
    echo
    echo "=== CHINOOK PRIVILEGES ==="

    if ! getent passwd chinook >/dev/null; then
        echo "CHINOOK: NOT PRESENT"
        return
    fi

    local uid shell status expiry

    uid="$(id -u chinook)"
    shell="$(getent passwd chinook | cut -d: -f7)"
    status="$(passwd -S chinook | awk '{print $2}')"
    expiry="$(getent shadow chinook | cut -d: -f8)"

    if [[ "$uid" -eq 0 ]]; then
        echo "ROOT EQUIVALENT (UID 0): YES"
    else
        echo "ROOT EQUIVALENT (UID 0): NO (UID $uid)"
    fi

    if id -nG chinook | tr ' ' '\n' | grep -Fxq sudo; then
        echo "SUDO GROUP: YES"
    else
        echo "SUDO GROUP: NO"
    fi

    echo "PASSWORD STATUS: $status"
    echo "LOGIN SHELL: $shell"
    echo "ACCOUNT EXPIRY: ${expiry:-never}"
}

audit() {
    echo
    echo "=== UID 0 ACCOUNTS ==="
    getent passwd | awk -F: '$3 == 0 {
        print $1, "UID=" $3
    }'

    echo
    echo "=== ACCOUNTS WITH USABLE PASSWORDS ==="

    while IFS=: read -r user rest; do
        status="$(passwd -S "$user" 2>/dev/null |
                  awk '{print $2}' || true)"

        if [[ "$status" == "P" ]]; then
            echo "$user"
        fi
    done < <(getent passwd)

    echo
    echo "=== ACCOUNTS WITH LOGIN SHELLS ==="

    getent passwd | awk -F: '
        $7 !~ /(nologin|false)$/ && $7 != "/bin/sync" {
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
    echo "=== SUDO GROUP ==="
    getent group sudo || true

    show_chinook

    echo
    echo "=== REQUIRED ACCOUNTS ==="

    for user in root itadmin backupsvc; do
        if getent passwd "$user" >/dev/null; then
            echo "$user: $(passwd -S "$user" | awk '{print $2}')"
        else
            echo "$user: NOT PRESENT"
        fi
    done

    echo
    echo "=== DIRECT CHINOOK SUDO RULES ==="

    grep -REn '^[[:space:]]*chinook[[:space:]]' \
        /etc/sudoers /etc/sudoers.d/ 2>/dev/null || true

    echo
    echo "=== SSH SECURITY ==="

    /usr/sbin/sshd -t

    /usr/sbin/sshd -T \
        -C user=itadmin,host=localhost,addr=127.0.0.1 |
        grep -E \
        '^(permitrootlogin|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|authenticationmethods) '
}

disable_chinook() {
    if ! getent passwd chinook >/dev/null; then
        echo "CHINOOK: NOT PRESENT - no changes."
        return
    fi

    local uid status shell expiry

    uid="$(id -u chinook)"

    if [[ "$uid" -eq 0 ]]; then
        echo "ERROR: chinook has UID 0."
        echo "Manual review required."
        return 1
    fi

    # Do not disrupt running services or sessions.
    if pgrep -u "$uid" >/dev/null 2>&1; then
        echo "ERROR: chinook has running processes."
        echo "Review them before disabling the account."
        return 1
    fi

    echo "=== DISABLING CHINOOK ==="

    usermod --lock chinook
    usermod --expiredate 1 chinook
    usermod --shell /usr/sbin/nologin chinook

    if id -nG chinook | tr ' ' '\n' | grep -Fxq sudo; then
        gpasswd -d chinook sudo
    fi

    echo
    echo "=== VERIFY CHINOOK ==="

    status="$(passwd -S chinook | awk '{print $2}')"
    shell="$(getent passwd chinook | cut -d: -f7)"
    expiry="$(getent shadow chinook | cut -d: -f8)"

    if [[ "$status" != "L" ||
          "$shell" != "/usr/sbin/nologin" ||
          "$expiry" != "1" ]]; then
        echo "ERROR: chinook disable verification failed."
        return 1
    fi

    if id -nG chinook | tr ' ' '\n' | grep -Fxq sudo; then
        echo "ERROR: chinook still belongs to sudo."
        return 1
    fi

    if grep -REq '^[[:space:]]*chinook[[:space:]]' \
        /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
        echo "WARNING: Direct chinook sudo rule exists."
        echo "Manual review required."
        return 1
    fi

    echo "CHINOOK: DISABLED"
    echo "Password locked."
    echo "Account expired."
    echo "Login shell disabled."
    echo "Sudo group removed."
}

case "${1:-}" in
    --status)
        audit
        ;;

    --apply)
        disable_chinook
        audit
        echo
        echo "USER AUDIT COMPLETED"
        ;;

    *)
        echo "Usage: $0 --status | --apply"
        exit 2
        ;;
esac


