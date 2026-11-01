
#!/usr/bin/env bash
set -euo pipefail

# Debian server bootstrap
# Run as root.

[[ $EUID -eq 0 ]] || {
    echo "ERROR: Run as root."
    exit 1
}

ADMIN="itadmin"
HOME_DIR="/home/$ADMIN"

echo "=== INSTALL PACKAGES ==="

apt-get update
apt-get install -y sudo git vim tmux openssh-server

echo "=== ADMIN ACCOUNT ==="

if ! id "$ADMIN" &>/dev/null; then
    adduser --disabled-password --gecos "" "$ADMIN"
fi

usermod -aG sudo "$ADMIN"

# Configure SSH public keys
install -d -m 700 -o "$ADMIN" -g "$ADMIN" \
    "$HOME_DIR/.ssh"

if [[ ! -e "$HOME_DIR/.ssh/authorized_keys" ]]; then
    if [[ -s /root/.ssh/authorized_keys ]]; then
        install -m 600 -o "$ADMIN" -g "$ADMIN" \
            /root/.ssh/authorized_keys \
            "$HOME_DIR/.ssh/authorized_keys"
    else
        echo "WARNING: Root authorized_keys is missing."
        echo "Install an approved SSH key for $ADMIN manually."
    fi
fi

# Set initial password only if necessary
if [[ "$(passwd -S "$ADMIN" | awk '{print $2}')" != "P" ]]; then
    passwd "$ADMIN"
fi

echo "=== DEFAULT EDITOR ==="

update-alternatives --set editor /usr/bin/vim.basic

echo "=== VERIFICATION ==="

id "$ADMIN"

ls -ld "$HOME_DIR/.ssh"

if [[ -f "$HOME_DIR/.ssh/authorized_keys" ]]; then
    ls -l "$HOME_DIR/.ssh/authorized_keys"
    ssh-keygen -lf "$HOME_DIR/.ssh/authorized_keys"
fi

visudo -c
/usr/sbin/sshd -t

echo
echo "Bootstrap completed."
echo "Test SSH login and sudo as $ADMIN before SSH hardening."


