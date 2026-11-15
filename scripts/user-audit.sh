
#!/usr/bin/env bash
set -euo pipefail

# Debian user audit and legacy chinook cleanup.
# Run as root.
# Never modifies root, itadmin or backupsvc.

[[ $EUID -eq 0 ]] || {
    echo "ERROR: Run as root." >&2
    exit 1
}

has_sudo() {
    id -nG "$1" | tr ' ' '\n' | grep -Fxq sudo
}

check_accounts() {
    echo "=== REQUIRED ACCOUNTS ==="

    for user in root itadmin; do
        getent passwd "$user" >/dev/null || {
            echo "ERROR: Required account missing: $user"
            return 1
        }
        echo "$user: PRESENT"
    done

    [[ "$(id -u root)" == 0 ]] || {
        echo "ERROR: root does not have UID 0."
        return 1
    }

    echo
    echo "=== BACKUP SERVICE ACCOUNT ==="

    if getent passwd backupsvc >/dev/null; then
        echo "BACKUPSVC: PRESENT"

        passwd -S backupsvc

        home=$(getent passwd backupsvc | cut -d: -f6)

        if [[ -s "$home/.ssh/authorized_keys" ]]; then
            echo "BACKUPSVC SSH KEYS: PRESENT"
        else
            echo "WARNING: BACKUPSVC SSH KEYS MISSING"
        fi

        if [[ "$(id -u backupsvc)" -eq 0 ]]; then
            echo "WARNING: backupsvc has UID 0!"
        fi

        expiry=$(getent shadow backupsvc | cut -d: -f8)
        if [[ -n "$expiry" ]] &&
           [[ "$expiry" -le "$(($(date +%s)/86400))" ]]; then
            echo "WARNING: backupsvc account is expired."
        fi
    else
        echo "WARNING: BACKUPSVC ACCOUNT IS MISSING"
        echo "Check whether this server is included in backups."
    fi
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
        status=$(passwd -S "$user" 2>/dev/null |
                 awk '{print $2}' || true)
        [[ "$status" == P ]] && echo "$user"
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

    echo
    echo "=== CHINOOK PRIVILEGES ==="

    if getent passwd chinook >/dev/null; then
        getent passwd chinook
        passwd -S chinook

        if [[ "$(id -u chinook)" -eq 0 ]]; then
            echo "CHINOOK UID 0: YES - ROOT EQUIVALENT"
        else
            echo "CHINOOK UID 0: NO"
        fi

        if has_sudo chinook; then
            echo "CHINOOK SUDO: YES"
        else
            echo "CHINOOK SUDO: NO"
        fi

        chage -l chinook |
            grep -E 'Account expires|Password expires' || true
    else
        echo "CHINOOK: NOT PRESENT"
    fi

    echo
    echo "=== DIRECT CHINOOK SUDO RULES ==="

    grep -REn '^[[:space:]]*chinook[[:space:]]' \
        /etc/sudoers /etc/sudoers.d 2>/dev/null || true

    echo
    check_accounts

    echo
    echo "=== SSH CONFIGURATION ==="

    /usr/sbin/sshd -t

    /usr/sbin/sshd -T \
        -C user=itadmin,host=localhost,addr=127.0.0.1 |
        grep -E \
        '^(permitrootlogin|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|authenticationmethods) '
}

migrate_uid_zero() {
    [[ "$(id -u chinook)" -eq 0 ]] || return 0

    echo "=== MIGRATE CHINOOK UID 0 ==="

    # Only support a unique local account entry.
    [[ "$(awk -F: '$1=="chinook"{n++} END{print n+0}' \
        /etc/passwd)" == 1 ]] || {
        echo "ERROR: chinook is not a unique local account."
        return 1
    }

    command -v python3 >/dev/null || {
        echo "ERROR: python3 is required for UID migration."
        return 1
    }

    command -v vipw >/dev/null || {
        echo "ERROR: vipw is required for UID migration."
        return 1
    }

    # Select a free UID, including NSS lookups.
    local new_uid="" candidate tmpdir editor

    for ((candidate=20000; candidate<=29999; candidate++)); do
        if ! getent passwd "$candidate" >/dev/null; then
            new_uid="$candidate"
            break
        fi
    done

    [[ -n "$new_uid" ]] || {
        echo "ERROR: No available UID in 20000-29999."
        return 1
    }

    echo "Changing chinook UID: 0 -> $new_uid"
    echo "Existing UID 0 files will remain root-owned."

    tmpdir=$(mktemp -d /run/chinook-uid.XXXXXXXX)
    editor="$tmpdir/editor"

    cat > "$editor" <<'PYTHON'
#!/usr/bin/python3
import os
import sys

path = sys.argv[1]
new_uid = os.environ["CHINOOK_NEW_UID"]

with open(path, encoding="utf-8") as f:
    lines = f.readlines()

matches = [
    i for i, line in enumerate(lines)
    if line.split(":", 1)[0] == "chinook"
]

if len(matches) != 1:
    sys.exit("ERROR: Invalid chinook entry count.")

i = matches[0]
fields = lines[i].rstrip("\n").split(":")

if len(fields) != 7 or fields[2] != "0":
    sys.exit("ERROR: Unexpected chinook passwd entry.")

fields[2] = new_uid
lines[i] = ":".join(fields) + "\n"

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
PYTHON

    chmod 700 "$editor"

    # vipw locks the account database during the edit.
    local result=0

    CHINOOK_NEW_UID="$new_uid" \
        EDITOR="$editor" VISUAL="$editor" vipw -q || result=$?

    rm -rf "$tmpdir"

    [[ "$result" -eq 0 ]] || {
        echo "ERROR: UID migration failed."
        return 1
    }

    [[ "$(id -u chinook)" == "$new_uid" ]] || {
        echo "ERROR: UID migration verification failed."
        return 1
    }

    echo "CHINOOK NEW UID: $new_uid"
}

disable_chinook() {
    echo
    echo "=== CHINOOK CLEANUP ==="

    if ! getent passwd chinook >/dev/null; then
        echo "CHINOOK: NOT PRESENT - no changes."
        return 0
    fi

    # Do not change account identities on a running job.
    # UID 0 processes cannot be distinguished from root processes.
    local uid
    uid=$(id -u chinook)

    if [[ "$uid" -ne 0 ]] &&
       pgrep -u "$uid" >/dev/null 2>&1; then
        echo "ERROR: chinook has running processes."
        return 1
    fi

    # Check named login sessions separately.
    if who | awk '$1=="chinook"{found=1} END{exit !found}'; then
        echo "ERROR: Active chinook login session detected."
        return 1
    fi

    echo "=== BACKUP ACCOUNT DATABASE ==="

    backup_dir=$(mktemp -d /root/user-audit.XXXXXXXX)

    cp -a /etc/passwd /etc/shadow \
          /etc/group /etc/gshadow "$backup_dir/"

    echo "Backup: $backup_dir"

    # Change a duplicate UID 0 entry before using usermod.
    migrate_uid_zero

    echo "=== DISABLE CHINOOK ==="

    usermod --lock chinook
    usermod --expiredate 1 chinook
    usermod --shell /usr/sbin/nologin chinook

    # Remove root group privileges if inherited by this account.
    if [[ "$(id -g chinook)" -eq 0 ]]; then
        if ! getent group chinook >/dev/null; then
            groupadd chinook-retired 2>/dev/null || true
            usermod -g chinook-retired chinook
        else
            usermod -g chinook chinook
        fi
    fi

    if has_sudo chinook; then
        gpasswd -d chinook sudo
    fi

    echo "=== VERIFY CHINOOK ==="

    [[ "$(id -u chinook)" -ne 0 ]] || {
        echo "ERROR: chinook still has UID 0."
        return 1
    }

    [[ "$(id -g chinook)" -ne 0 ]] || {
        echo "ERROR: chinook still has GID 0."
        return 1
    }

    [[ "$(passwd -S chinook | awk '{print $2}')" == L ]] || {
        echo "ERROR: chinook password is not locked."
        return 1
    }

    [[ "$(getent passwd chinook | cut -d: -f7)" \
       == "/usr/sbin/nologin" ]] || {
        echo "ERROR: chinook login shell is not disabled."
        return 1
    }

    [[ "$(getent shadow chinook | cut -d: -f8)" == 1 ]] || {
        echo "ERROR: chinook account is not expired."
        return 1
    }

    if has_sudo chinook; then
        echo "ERROR: chinook still belongs to sudo."
        return 1
    fi

    if grep -REq '^[[:space:]]*chinook[[:space:]]' \
        /etc/sudoers /etc/sudoers.d 2>/dev/null; then
        echo "WARNING: Direct chinook sudo rule remains."
        return 1
    fi

    echo "CHINOOK: DISABLED SUCCESSFULLY"
}

case "${1:-}" in
    --status)
        audit
        ;;

    --apply)
        check_accounts
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

