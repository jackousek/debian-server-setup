
#!/usr/bin/env bash
set -euo pipefail

# Standardize Debian SSH configuration.
# Run as root after verifying itadmin and backupsvc SSH access.

[[ $EUID -eq 0 ]] || {
    echo "ERROR: Run as root."
    exit 1
}

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

MAIN="/etc/ssh/sshd_config"
DEFAULT="/usr/share/openssh/sshd_config"
SOURCE="$REPO_DIR/ssh/01-admin-hardening.conf"
TARGET="/etc/ssh/sshd_config.d/01-admin-hardening.conf"

echo "=== PRE-FLIGHT CHECKS ==="

for file in "$MAIN" "$DEFAULT" "$SOURCE"; do
    [[ -s "$file" ]] || {
        echo "ERROR: Missing file: $file"
        exit 1
    }
done

[[ -s /home/itadmin/.ssh/authorized_keys ]] || {
    echo "ERROR: itadmin SSH keys are missing."
    exit 1
}

# The Debian reference must support configuration drop-ins.
grep -Fxq \
    'Include /etc/ssh/sshd_config.d/*.conf' \
    "$DEFAULT" || {
    echo "ERROR: Debian reference has no Include directive."
    exit 1
}

# Verify current SSH configuration.
/usr/sbin/sshd -t

echo
echo "=== CURRENT CONFIGURATION DIFFERENCES ==="

diff -u "$DEFAULT" "$MAIN" || true

echo
echo "=== EXISTING SSH DROP-INS ==="
ls -la /etc/ssh/sshd_config.d/ 2>/dev/null || true

echo
echo "=== WARNING ==="
echo "Review the differences and existing drop-ins."
echo "Custom SSH settings may be removed or overridden."
echo
echo "Before continuing, verify:"
echo "- itadmin SSH key login and sudo"
echo "- backupsvc SSH key access"
echo "- Other SSH service accounts and dependencies"
echo "- Console or recovery access"
echo
echo "Keep your current SSH session open."

read -r -p "Type YES to continue: " ANSWER
[[ "$ANSWER" == "YES" ]] || exit 1

echo
echo "=== BACKUP ==="

BACKUP="$(mktemp -d /root/ssh-migration.XXXXXXXX)"

cp -a "$MAIN" "$BACKUP/sshd_config"

if [[ -e "$TARGET" ]]; then
    cp -a "$TARGET" "$BACKUP/01-admin-hardening.conf"
    touch "$BACKUP/had-dropin"
fi

echo "Backup directory: $BACKUP"

restore() {
    echo "ERROR: Restoring previous SSH configuration."

    cp -a "$BACKUP/sshd_config" "$MAIN"

    if [[ -f "$BACKUP/had-dropin" ]]; then
        cp -a "$BACKUP/01-admin-hardening.conf" "$TARGET"
    else
        rm -f "$TARGET"
    fi
}

# Restore previous configuration if deployment fails.
trap restore EXIT

echo
echo "=== INSTALL DEBIAN SSH CONFIGURATION ==="

install -d -m 755 /etc/ssh/sshd_config.d

install -o root -g root -m 644 \
    "$DEFAULT" "$MAIN"

echo
echo "=== INSTALL SECURITY POLICY ==="

install -o root -g root -m 644 \
    "$SOURCE" "$TARGET"

echo
echo "=== VALIDATE SSH CONFIGURATION ==="

/usr/sbin/sshd -t

POLICY="$(
    /usr/sbin/sshd -T \
        -C user=itadmin,host=localhost,addr=127.0.0.1
)"

for setting in \
    "permitrootlogin no" \
    "pubkeyauthentication yes" \
    "passwordauthentication no" \
    "kbdinteractiveauthentication no" \
    "authenticationmethods publickey" \
    "allowagentforwarding no" \
    "allowtcpforwarding yes"
do
    if ! grep -Fxq "$setting" <<< "$POLICY"; then
        echo "ERROR: Policy not effective: $setting"
        exit 1
    fi
done

# Check root SSH policy.
ROOT_POLICY="$(
    /usr/sbin/sshd -T \
        -C user=root,host=localhost,addr=127.0.0.1
)"

grep -Fxq "permitrootlogin no" <<< "$ROOT_POLICY" || {
    echo "ERROR: Root SSH login is not disabled."
    exit 1
}

# Check backupsvc policy if the account exists.
if id backupsvc &>/dev/null; then
    echo
    echo "=== CHECK BACKUPSVC ==="

    BACKUP_POLICY="$(
        /usr/sbin/sshd -T \
            -C user=backupsvc,host=localhost,addr=127.0.0.1
    )"

    for setting in \
        "pubkeyauthentication yes" \
        "passwordauthentication no"
    do
        if ! grep -Fxq "$setting" <<< "$BACKUP_POLICY"; then
            echo "ERROR: backupsvc policy: $setting"
            exit 1
        fi
    done

    echo "backupsvc SSH policy: OK"
fi

echo
echo "=== RELOAD SSH ==="

systemctl reload ssh.service

# Deployment successful.
trap - EXIT

echo
echo "=== COMPLETED ==="
echo "Original Debian configuration installed."
echo "Git-managed SSH security policy installed."
echo "Backup: $BACKUP"
echo
echo "IMPORTANT:"
echo "Test a NEW itadmin SSH connection immediately."
echo "Verify backupsvc access from the backup server."
echo "Keep the original session open until testing succeeds."
echo "No timed automatic rollback is configured."


