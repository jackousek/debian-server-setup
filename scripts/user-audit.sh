
#!/usr/bin/env bash
set -euo pipefail

# Debian user audit and legacy chinook cleanup.
# Run as root.
# Never modifies root, itadmin or backupsvc.

[[ $EUID -eq 0 ]] || {
    echo "ERROR: Run as root."
    exit 1
}

audit() {
    echo
    echo "=== UID 0 ACCOUNTS ==="
    getent passwd | awk -F: '$3 == 0 {
        print $1, "UID=" $3
    }'

    echo
    echo "=== ACCOUNTS WITH PASSWORDS ==="
    while IFS=: read -r user rest; do
        status=$(passwd -S "$user" 2>/dev/null |
                 awk '{print $2}' || true)
        [[ "$status" == P ]] && echo "$user"
    done < <(getent passwd)

    echo
    echo "=== LOGIN SHELLS ==="
    getent passwd | awk -F: '
        $7 !~ /(nologin|false)$/ && $7 != "/bin/sync" {
            print $1, "UID=" $3, "SHELL=" $7
        }'

    echo
    echo "=== SUDO GROUP ==="
    getent group sudo || true

    echo
    echo "=== CHINOOK ==="
    if getent passwd chinook >/dev/null; then
        getent passwd chinook
        passwd -S chinook
        chage -l chinook | grep "Account expires"

        if [[ $(id -u chinook) -eq 0 ]]; then
            echo "CHINOOK ROOT EQUIVALENT: YES"
        else
            echo "CHINOOK ROOT EQUIVALENT: NO"
        fi

        if id -nG chinook | tr ' ' '\n' |
           grep -Fxq sudo; then
            echo "CHINOOK SUDO: YES"
        else
            echo "CHINOOK SUDO: NO"
        fi
    else
        echo "CHINOOK: NOT PRESENT"
    fi

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
        /etc/sudoers /etc/sudoers.d 2>/dev/null || true
}

change_chinook_uid() {
    local uid new_uid workdir editor_script

    uid=$(id -u chinook)

    # Only migrate a duplicate UID 0 account.
    [[ "$uid" -eq 0 ]] || return 0

    echo "=== CHINOOK HAS UID 0 ==="

    # Require a normal, local root account.
    [[ "$(getent passwd root | cut -d: -f3)" == 0 ]] || {
        echo "ERROR: Invalid root account."
        return 1
    }

    # This migration only supports a local passwd entry.
    [[ "$(awk -F: '$1=="chinook"{n++} END{print n+0}' \
        /etc/passwd)" == 1 ]] || {
        echo "ERROR: chinook is not a unique local account."
        return 1
    }

    command -v vipw >/dev/null
    command -v python3 >/dev/null

    # Choose an unused UID.
    new_uid=""
    for candidate in $(seq 20000 29999); do
        if ! getent passwd "$candidate" >/dev/null; then
            new_uid="$candidate"
            break
        fi
    done

    [[ -n "$new_uid" ]] || {
        echo "ERROR: No available UID."
        return 1
    }

    echo "Changing chinook UID: 0 -> $new_uid"
    echo "Root-owned files will NOT be chowned."

    workdir=$(mktemp -d /run/chinook-uid.XXXXXXXX)
    editor_script="$workdir/editor"
    
    cat > "$editor_script" <<'PYTHON'
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
    sys.exit("Invalid chinook entry count")

i = matches[0]
fields = lines[i].rstrip("\n").split(":")

if len(fields) != 7 or fields[2] != "0":
    sys.exit("Unexpected chinook passwd entry")

fields[2] = new_uid
lines[i] = ":".join(fields) + "\n"

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
PYTHON

    chmod 700 "$editor_script"

    # vipw locks the passwd database while editing.
    if ! CHINOOK_NEW_UID="$new_uid" \
         EDITOR="$editor_script" \
         VISUAL="$editor_script" vipw; then
        rm -f "$editor_script"
        rmdir "$workdir"
        echo "ERROR: UID migration failed."
        return 1
    fi

    rm -f "$editor_script"
    rmdir "$workdir"

    [[ "$(id -u chinook)" == "$new_uid" ]] || {
        echo "ERROR: UID verification failed."
        return 1
    }

    echo "CHINOOK UID: $new_uid"
}

apply() {
    echo "=== USER SECURITY CLEANUP ==="

    if ! getent passwd chinook >/dev/null; then
        echo "CHINOOK: NOT PRESENT"
        audit
        return
    fi

    # Ensure required administrator accounts exist.
    for user in root itadmin backupsvc; do
        getent passwd "$user" >/dev/null || {
            echo "ERROR: Required account missing: $user"
            return 1
        }
    done

    # A legacy account with UID 0 shares root's process identity.
    # Never attempt to kill processes by its UID.
    if [[ $(id -u chinook) -ne 0 ]]; then
        if pgrep -u "$(id -u chinook)" >/dev/null; then
            echo "ERROR: chinook has running processes."
            return 1
        fi
    fi

    echo "=== DISABLE CHINOOK LOGIN ==="

    usermod --lock chinook
    usermod --expiredate 1 chinook
    usermod --shell /usr/sbin/nologin chinook

    change_chinook_uid

    echo "=== REMOVE SUDO GROUP ==="

    if id -nG chinook | tr ' ' '\n' |
       grep -Fxq sudo; then
        gpasswd -d chinook sudo
    fi

    echo "=== VERIFY ==="

    [[ $(id -u chinook) -ne 0 ]] || {
        echo "ERROR: chinook still has UID 0."
        return 1
    }

    [[ $(passwd -S chinook | awk '{print $2}') == L ]] || {
        echo "ERROR: Password is not locked."
        return 1
    }

    [[ $(getent passwd chinook | cut -d: -f7) \
       == /usr/sbin/nologin ]] || {
        echo "ERROR: Login shell is still enabled."
        return 1
    }

    [[ $(getent shadow chinook | cut -d: -f8) == 1 ]] || {
        echo "ERROR: Account is not expired."
        return 1
    }

    if id -nG chinook | tr ' ' '\n' |
       grep -Fxq sudo; then
        echo "ERROR: chinook still belongs to sudo."
        return 1
    fi

    if grep -REq '^[[:space:]]*chinook[[:space:]]' \
       /etc/sudoers /etc/sudoers.d 2>/dev/null; then
        echo "WARNING: Direct chinook sudo rule remains."
        return 1
    fi

    echo "CHINOOK: DISABLED SUCCESSFULLY"
    audit
}

case "${1:-}" in
    --status)
        audit
        ;;
    --apply)
        apply
        ;;
    *)
        echo "Usage: $0 --status | --apply"
        exit 2
        ;;
esac

