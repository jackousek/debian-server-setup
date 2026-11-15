
#!/usr/bin/env bash
set -euo pipefail

# Restore Debian's original SSH configuration.
# Install our Git-managed security policy.
# Run as root.

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
        echo "ERROR: Missing $file"
        exit 1
    }
done

[[ -s /home/itadmin/.ssh/authorized_keys ]] || {
    echo "ERROR: itadmin has no authorized_keys."
    exit 1
}

# Verify the reference belongs to the installed package version.
EXPECTED="$(
    dpkg-query -W -f='${Conffiles}\n' openssh-server |
        awk '$1 == "/etc/ssh/sshd_config" {print $2}'
)"

ACTUAL="$(md5sum "$DEFAULT" | awk '{print $1}')"

if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
    echo "ERROR: Debian reference does not match the package."
    echo "Review this server manually."
    exit 1
fi

grep -Fxq \
    'Include /etc/ssh/sshd_config.d/*.conf' \
    "$DEFAULT" || {
    echo "ERROR: Debian configuration lacks Include."
    exit 1
}

/usr/sbin/sshd -t

echo
echo "=== CURRENT CONFIGURATION DIFFERENCES ==="

diff -u "$DEFAULT" "$MAIN" || true

echo
echo "WARNING: Review the differences above."
echo "Custom ports, Match rules or backup access may be affected."
echo "Verify itadmin SSH key login and sudo first."
echo "Keep your existing SSH session open."

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

restore() {
    echo "Restoring previous SSH configuration..."

    cp -a "$BACKUP/sshd_config" "$MAIN"

    if [[ -f "$BACKUP/had-dropin" ]]; then
        cp -a "$BACKUP/01-admin-hardening.conf" "$TARGET"
    else
        rm -f "$TARGET"
    fi
}

# Restore files if any later command fails unexpectedly.
trap restore EXIT

echo
echo "=== INSTALL CONFIGURATION ==="

install -d -m 755 /etc/ssh/sshd_config.d

install -o root -g root -m 644 \
    "$DEFAULT" "$MAIN"

install -o root -g root -m 644 \
    "$SOURCE" "$TARGET"

echo
echo "=== VALIDATE SSH ==="

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
    "allowagentforwarding no"
do
    if ! grep -Fxq "$setting" <<< "$POLICY"; then
        echo "ERROR: Policy not effective: $setting"
        exit 1
    fi
done

# Also verify the root login policy.
ROOT_POLICY="$(
    /usr/sbin/sshd -T \
        -C user=root,host=localhost,addr=127.0.0.1
)"

grep -Fxq "permitrootlogin no" <<< "$ROOT_POLICY" || {
    echo "ERROR: Root SSH login is not disabled."
    exit 1
}

echo
echo "=== RELOAD SSH ==="

systemctl reload ssh.service

# Deployment succeeded: disable automatic restoration.
trap - EXIT

echo
echo "SSH configuration successfully deployed."
echo "Backup: $BACKUP"
echo
echo "IMPORTANT: Test a NEW itadmin SSH login now."
echo "No timed automatic rollback is configured."


