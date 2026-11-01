#!/usr/bin/env bash
set -euo pipefail

# Run as root on Debian. Does not change SSH policy or disable services.
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }

ADMIN=itadmin
HOME_DIR=/home/$ADMIN
REPO=https://github.com/jackousek/dotfiles.git

apt-get update
apt-get install -y sudo git vim tmux openssh-server

if ! id "$ADMIN" >/dev/null 2>&1; then
    adduser --disabled-password --gecos '' "$ADMIN"
fi
usermod -aG sudo "$ADMIN"

# Add authorized keys only if the account does not already have them.
install -d -m 700 -o "$ADMIN" -g "$ADMIN" "$HOME_DIR/.ssh"
if [[ ! -e "$HOME_DIR/.ssh/authorized_keys" ]]; then
    if [[ -s /root/.ssh/authorized_keys ]]; then
        install -m 600 -o "$ADMIN" -g "$ADMIN" \
            /root/.ssh/authorized_keys "$HOME_DIR/.ssh/authorized_keys"
    else
        echo 'WARNING: No root SSH keys to copy; install an itadmin key manually.'
    fi
fi

# Set password only when the account does not have a usable password.
if [[ "$(passwd -S "$ADMIN" | awk '{print $2}')" != P ]]; then
    passwd "$ADMIN"
fi

# Use a separate clone owned by itadmin, not the root checkout.
if [[ ! -e "$HOME_DIR/dotfiles" ]]; then
    runuser -u "$ADMIN" -- git clone "$REPO" "$HOME_DIR/dotfiles"
fi
[[ -f "$HOME_DIR/dotfiles/vim/.vimrc" ]] || { echo 'Missing dotfiles repository contents.' >&2; exit 1; }

# Preserve original files; symlinks follow updates to the local Git clone.
for name in vimrc tmux.conf; do
    case "$name" in
        vimrc) source_file="$HOME_DIR/dotfiles/vim/.vimrc"; target="$HOME_DIR/.vimrc" ;;
        tmux.conf) source_file="$HOME_DIR/dotfiles/tmux/.tmux.conf"; target="$HOME_DIR/.tmux.conf" ;;
    esac
    if [[ -L "$target" && "$(readlink "$target")" == "$source_file" ]]; then
        continue
    fi
    if [[ -e "$target" || -L "$target" ]]; then
        mv "$target" "$target.backup.$(date +%Y%m%d%H%M%S)"
    fi
    ln -s "$source_file" "$target"
    chown -h "$ADMIN:$ADMIN" "$target"
done

# Keep Debian's original .bashrc and source the Git-managed settings.
BASHRC="$HOME_DIR/.bashrc"
if [[ ! -f "$BASHRC" ]]; then
    install -m 644 -o "$ADMIN" -g "$ADMIN" /etc/skel/.bashrc "$BASHRC"
fi
if ! grep -Fq '# dotfiles bash configuration' "$BASHRC"; then
    cat >> "$BASHRC" <<'BLOCK'

# dotfiles bash configuration
[ -f "$HOME/dotfiles/bash/.bashrc" ] && . "$HOME/dotfiles/bash/.bashrc"
BLOCK
fi
chown "$ADMIN:$ADMIN" "$BASHRC"

# Set Vim as the default editor without opening an interactive menu.
if [[ -x /usr/bin/vim.basic ]]; then
    update-alternatives --set editor /usr/bin/vim.basic
fi

id "$ADMIN"
echo 'Bootstrap complete. In a SECOND terminal, test SSH key login and sudo -v.'
echo 'SSH hardening and service cleanup are separate operations.'
