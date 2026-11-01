
# Debian Server Setup

Simple Bash scripts for initial Debian server configuration.

## 1. Installation (root)

Log in to the target Debian server as root.

```bash
apt update && apt install -y git

mkdir -p /root/git
cd /root/git

git clone https://github.com/jackousek/debian-server-setup.git
cd debian-server-setup

bash scripts/bootstrap.sh
```

Bootstrap performs:
- Install sudo, Git, Vim, tmux and OpenSSH.
- Create `itadmin` and add it to the sudo group.
- Copy root's authorized SSH keys if `itadmin` has none.
- Set the initial administrator password.
- Set Vim as the default editor.
- Validate sudo and SSH configuration.

## 2. Verify administrator (itadmin)

Open a new SSH session. Keep the root session open.

```bash
ssh itadmin@SERVER_IP

id
sudo -v
```

Confirm that SSH public-key login and sudo work.

## 3. Install dotfiles (itadmin)

Run as `itadmin`:

```bash
cd ~
git clone https://github.com/jackousek/dotfiles.git
```

Back up existing configuration files if present:

```bash
[ ! -e ~/.vimrc ] || mv ~/.vimrc ~/.vimrc.bak
[ ! -e ~/.tmux.conf ] || mv ~/.tmux.conf ~/.tmux.conf.bak
```

Create symlinks:

```bash
ln -s ~/dotfiles/vim/.vimrc ~/.vimrc
ln -s ~/dotfiles/tmux/.tmux.conf ~/.tmux.conf
```

Keep Debian's original `.bashrc` and add the Git settings:

```bash
echo '[ -f "$HOME/dotfiles/bash/.bashrc" ] && . "$HOME/dotfiles/bash/.bashrc"' >> ~/.bashrc
source ~/.bashrc
```

Only run this dotfiles installation once.

## 4. SSH hardening (root)

Before deployment:
- Verify `itadmin` SSH key login and sudo.
- Check backup and automation accounts using SSH.
- Keep the existing SSH session open.
- Ensure console recovery is available.

Check that `/etc/ssh/sshd_config` contains:

```text
Include /etc/ssh/sshd_config.d/*.conf
```

If missing, back up the file and add the Include directive
near the beginning using Vim. Validate with `sshd -t`.

Then deploy:

```bash
cd /root/git/debian-server-setup
bash scripts/apply-ssh-hardening.sh
```

The script installs the Git-managed SSH policy into:

```text
/etc/ssh/sshd_config.d/01-admin-hardening.conf
```

The policy disables SSH password and root login.

IMPORTANT: The script has no automatic rollback for SSH
authentication failures. Test a new SSH login immediately.

## 5. Optional cleanup (root)

Check current services:

```bash
bash scripts/cleanup-optional.sh --status
```

Disable NRPE only after verifying replacement monitoring:

```bash
bash scripts/cleanup-optional.sh --disable-nrpe
```

Expire the legacy account only after checking dependencies:

```bash
bash scripts/cleanup-optional.sh --expire-chinook
```

## 6. Updates

Update server scripts as root:

```bash
cd /root/git/debian-server-setup
git pull --ff-only
```

Update dotfiles as `itadmin`:

```bash
cd ~/dotfiles
git pull --ff-only
```

Git updates do not automatically apply SSH security changes.

## Security

- Run server setup scripts as root.
- Use `itadmin` for normal administration.
- Never store passwords or private keys in Git.
- Verify SSH access before disabling root login.
- Check service dependencies before disabling anything.


