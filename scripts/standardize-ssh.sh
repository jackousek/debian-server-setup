
#!/usr/bin/env bash
set -euo pipefail

# Standardize Debian SSH configuration.
# Run as root after verifying itadmin SSH access.

[[ $EUID -eq 0 ]] || {
    echo "ERROR: Run as root."
    exit 1
}

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

MAIN="/etc/ssh/sshd_config"
DEFAULT="/usr/share/openssh/sshd_config"
SOURCE="$REPO_DIR/ssh/01-admin-hardening.conf"
TARGET="/etc/ssh/sshd_config.d/01-admin-hardening.conf"

BACKUP=""
DEPLOYING=false

echo "=== 1. PRE-FLIGHT CHECKS ==="

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

# Debian reference must support configuration drop-ins.
grep -Fxq \
    'Include /etc/ssh/sshd_config.d/*.conf' \
    "$DEFAULT" || {
    echo "ERROR: Debian reference lacks Include directive."
    exit 1
}

# Validate the current configuration.
/usr/sbin/sshd -t

systemctl is-active --quiet ssh.service || {
    echo "ERROR: SSH service is not running."
    exit 1
}

echo
echo "=== 2. CURRENT CONFIGURATION ==="

diff -u "$DEFAULT" "$MAIN" || true

echo
echo "=== EXISTING SSH DROP-INS ==="

ls -la /etc/ssh/sshd_config.d/ 2>/dev/null || true

echo
echo "WARNING:"
echo "Review custom SSH settings before continuing."
echo "Check ports, Match rules, backup accounts and tunnels."
echo
echo "Verify a NEW itadmin SSH key login and sudo."
echo "Keep your existing SSH connection open."
echo "Ensure console recovery access is available."

read -r -p "Type YES to continue: " ANSWER
[[ "$ANSWER" == "YES" ]] || exit 1

echo
echo "=== 3. BACKUP ==="

BACKUP="$(mktemp -d /root/ssh-migration.XXXXXXXX)"

cp -a "$MAIN" "$BACKUP/sshd_config"

if [[ -e "$TARGET" ]]; then
    cp -a "$TARGET" "$BACKUP/01-admin-hardening.conf"
    touch "$BACKUP/had-dropin"
fi

echo "Backup: $BACKUP"

restore() {
    if [[ "$DEPLOYING" != true ]]; then
        return
    fi

    echo
    echo "ERROR: Restoring previous SSH configuration."

    cp -a "$BACKUP/sshd_config" "$MAIN"

    if [[ -f "$BACKUP/had-dropin" ]]; then
        cp -a "$BACKUP/01-admin-hardening.conf" "$TARGET"
    else
        rm -f "$TARGET"
    fi

    # Try to restore the previously active SSH policy.
    if /usr/sbin/sshd -t; then
        systemctl reload ssh.service || true
    else
        echo "WARNING: Restored files require manual SSH repair."
    fi
}

# Roll back file changes if deployment fails.
trap restore EXIT

DEPLOYING=true

echo
echo "=== 4. INSTALL DEBIAN CONFIGURATION ==="

install -d -m 755 /etc/ssh/sshd_config.d

install -o root -g root -m 644 \
    "$DEFAULT" "$MAIN"

echo
echo "=== 5. INSTALL SECURITY POLICY ==="

install -o root -g root -m 644 \
    "$SOURCE" "$TARGET"

echo
echo "=== 6. VALIDATE SSH SYNTAX ==="

/usr/sbin/sshd -t

echo "SSH syntax: OK"

echo
echo "=== 7. VERIFY SECURITY POLICY ==="

check_policy() {
    local user="$1"
    local setting="$2"
    local policy

    policy="$(
        /usr/sbin/sshd -T \
            -C user="$user",host=localhost,addr=127.0.0.1
    )"

    if ! grep -Fxq "$setting" <<< "$policy"; then
        echo "ERROR: $user: $setting is not effective."
        return 1
    fi
}

# Administrator security.
for setting in \
    "permitrootlogin no" \
    "pubkeyauthentication yes" \
    "passwordauthentication no" \
    "kbdinteractiveauthentication no" \
    "authenticationmethods publickey" \
    "allowagentforwarding no" \
    "allowtcpforwarding yes"
do
    check_policy itadmin "$setting"
done

# Root must not authenticate through SSH.
check_policy root "permitrootlogin no"

# Preserve key authentication for the backup service account.
if id backupsvc &>/dev/null; then

    echo "Checking backupsvc..."

    check_policy backupsvc "pubkeyauthentication yes"
    check_policy backupsvc "passwordauthentication no"
    check_policy backupsvc "authenticationmethods publickey"

    echo "backupsvc SSH policy: OK"
fi

echo "SSH security policy: OK"

echo
echo "=== 8. RELOAD SSH ==="

systemctl reload ssh.service

echo
echo "=== 9. VERIFY SSH SERVICE ==="

systemctl is-active --quiet ssh.service || {
    echo "ERROR: SSH service is not running."
    exit 1
}

/usr/sbin/sshd -t

systemctl status ssh.service --no-pager --lines=10

echo
echo "=== 10. VERIFY LISTENING SOCKETS ==="

ss -lntp | grep -E 'sshd|:22[[:space:]]' || true

# Deployment succeeded. Disable rollback.
DEPLOYING=false
trap - EXIT

echo
echo "=== SSH STANDARDIZATION COMPLETE ==="
echo
echo "Debian SSH configuration installed."
echo "Git-managed security policy installed."
echo "SSH configuration validated."
echo "SSH service reloaded successfully."
echo "SSH service is active."
echo
echo "Backup: $BACKUP"
echo
echo "IMPORTANT:"
echo "1. Test a NEW SSH connection as itadmin."
echo "2. Verify sudo access."
echo "3. Test backupsvc from the backup server."
echo "4. Keep the original SSH session open."
echo
echo "No timed automatic rollback is configured."


