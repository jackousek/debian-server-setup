#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SOURCE="$REPO_DIR/ssh/01-admin-hardening.conf"
TARGET=/etc/ssh/sshd_config.d/01-admin-hardening.conf

[[ -s "$SOURCE" ]] || { echo "Missing $SOURCE" >&2; exit 1; }
[[ -s /home/itadmin/.ssh/authorized_keys ]] || {
    echo 'Missing itadmin authorized_keys; do not disable password login.' >&2
    exit 1
}
/usr/sbin/sshd -t

echo 'WARNING: This enables public-key-only SSH authentication and disables root SSH login.'
echo 'First verify a NEW itadmin SSH session and sudo -v. Keep console/recovery access.'
read -r -p 'Type YES to deploy: ' reply
[[ "$reply" == YES ]] || exit 1

install -d -m 755 /etc/ssh/sshd_config.d
BACKUP="$(mktemp -d /root/ssh-backup.XXXXXXXX)"
if [[ -e "$TARGET" ]]; then
    cp -a "$TARGET" "$BACKUP/original.conf"
    echo yes > "$BACKUP/had-original"
fi

restore() {
    if [[ -f "$BACKUP/had-original" ]]; then
        cp -a "$BACKUP/original.conf" "$TARGET"
    else
        rm -f "$TARGET"
    fi
}

install -o root -g root -m 644 "$SOURCE" "$TARGET"
if ! /usr/sbin/sshd -t; then
    restore
    echo 'Invalid SSH configuration: restored previous file.' >&2
    exit 1
fi

# Check the effective default policy; Match rules can still vary by user/IP.
POLICY="$(/usr/sbin/sshd -T -C user=itadmin,host=localhost,addr=127.0.0.1)"
for setting in 'permitrootlogin no' 'passwordauthentication no' \
               'kbdinteractiveauthentication no' 'authenticationmethods publickey'; do
    if ! grep -Fxq "$setting" <<< "$POLICY"; then
        restore
        echo "Policy not effective: $setting; restored previous file." >&2
        exit 1
    fi
done

if ! systemctl reload ssh.service; then
    restore
    systemctl reload ssh.service || true
    echo 'SSH reload failed: attempted to restore previous configuration.' >&2
    exit 1
fi

echo "SSH configuration installed. Backup: $BACKUP"
echo 'Test another SSH login NOW. This simple script has NO automatic rollback.'
