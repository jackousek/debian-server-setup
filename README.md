
# Debian Server Setup

Standard setup, security and maintenance for Debian servers.

Repository:
https://github.com/jackousek/debian-server-setup

# QUICK START — EVERY SERVER

Run commands as root unless stated otherwise.

## 1. Get scripts

On a new server:

```bash
apt update && apt install -y git
mkdir -p /root/git
cd /root/git
git clone https://github.com/jackousek/debian-server-setup.git
cd debian-server-setup
```

On an existing server with the repository:

```bash
cd /root/git/debian-server-setup
git pull --ff-only
```

## 2. SECURITY

- [ ] Create and verify itadmin
- [ ] Install dotfiles as itadmin (optional)
- [ ] Standardize SSH configuration
- [ ] Audit user accounts
- [ ] Disable chinook
- [ ] Verify backupsvc SSH access
- [ ] Review unnecessary services
- [ ] Enable automatic security updates
- [ ] Verify SSH and monitoring

Run as root:

```bash
bash scripts/bootstrap.sh
```

Open a NEW SSH session as itadmin and verify:

```bash
id
sudo -v
```

Keep the original root session open.

After reviewing existing SSH settings and confirming
that backupsvc and other required SSH accounts are supported:

```bash
bash scripts/standardize-ssh.sh
```

Immediately test a NEW itadmin SSH connection.

Audit user accounts:

```bash
bash scripts/user-audit.sh --status
```

After reviewing dependencies, disable chinook:

```bash
bash scripts/user-audit.sh --disable-chinook
```

Check unnecessary services:

```bash
bash scripts/cleanup-optional.sh --status
```

Disable NRPE only if no longer required:

```bash
bash scripts/cleanup-optional.sh --disable-nrpe
```

NFS and RPC must be reviewed separately.
The cleanup script does not disable them.

Enable automatic security updates:

```bash
bash scripts/enable-security-updates.sh
```

Review the script's dry-run output and allowed repositories.
Verify CheckMK monitoring and important applications.

SECURITY OK = All checks passed.

## 3. BACKUP

- [ ] Create timestamp test file
- [ ] Wait for next scheduled rsync backup
- [ ] Verify the file on the backup server
- [ ] Confirm backup failure email alerts

On production server:

```bash
bash scripts/create-backup-test.sh
```

The script creates:

```text
/root/backup-test.txt
```

After the next backup, locate the file on the backup
server and compare its hostname and timestamp.

This test requires /root to be included in the backup.

BACKUP OK = Test file transferred successfully and
backup failure notifications are configured.

This checks one file transfer, not a full restore.

## 4. UPDATE

- [ ] Verify backup before updating
- [ ] Check Debian version
- [ ] Review pending packages
- [ ] Perform package updates
- [ ] Reboot if required
- [ ] Verify services and applications
- [ ] Verify CheckMK monitoring

Check:

```bash
cat /etc/os-release
apt update
apt list --upgradable
apt-get -s upgrade
```

Perform regular package upgrade:

```bash
apt upgrade
```

After updating:

```bash
systemctl --failed
systemctl list-units --type=service --state=running
```

Check whether a reboot is required:

```bash
test -f /run/reboot-required && cat /run/reboot-required
```

Reboot during a maintenance window if required.

Verify SSH, databases, applications, backups and monitoring.

IMPORTANT:
apt upgrade is NOT a major Debian version upgrade.
Major upgrades (for example Debian 12 to 13)
require a separate procedure.

UPDATE OK = Packages updated and services verified.

---

# ADDITIONAL COMMANDS

## Install dotfiles — ITADMIN

Log in as itadmin.

Run once:

```bash
cd ~
git clone https://github.com/jackousek/dotfiles.git
```

Back up existing configuration files:

```bash
[ ! -e ~/.vimrc ] && [ ! -L ~/.vimrc ] || mv ~/.vimrc ~/.vimrc.bak
[ ! -e ~/.tmux.conf ] && [ ! -L ~/.tmux.conf ] || mv ~/.tmux.conf ~/.tmux.conf.bak
```

Create symlinks:

```bash
ln -s ~/dotfiles/vim/.vimrc ~/.vimrc
ln -s ~/dotfiles/tmux/.tmux.conf ~/.tmux.conf
```

Load Git-managed Bash configuration:

```bash
echo '[ -f "$HOME/dotfiles/bash/.bashrc" ] && . "$HOME/dotfiles/bash/.bashrc"' >> ~/.bashrc
source ~/.bashrc
```

## Update dotfiles — ITADMIN

```bash
git -C ~/dotfiles pull --ff-only
```

## Update server scripts — ROOT

```bash
git -C /root/git/debian-server-setup pull --ff-only
```

## Update SSH security policy — ROOT

Use only when the SSH policy changes in Git:

```bash
cd /root/git/debian-server-setup
bash scripts/apply-ssh-hardening.sh
```

Keep the existing SSH session open and test a new login.

---

# SCRIPT REFERENCE

| Script | Purpose |
|---|---|
| bootstrap.sh | Create itadmin, install packages, configure sudo |
| standardize-ssh.sh | Restore Debian SSH defaults and apply security policy |
| apply-ssh-hardening.sh | Update SSH security policy only |
| user-audit.sh | Audit users and disable chinook |
| cleanup-optional.sh | Check NFS/RPC/NRPE and optionally disable NRPE |
| enable-security-updates.sh | Configure daily automatic security updates |
| create-backup-test.sh | Generate timestamp file for rsync test |

All scripts are located in:

```text
/root/git/debian-server-setup/scripts/
```

# SECURITY POLICY

root:
- Password retained for console recovery.
- SSH login disabled.

itadmin:
- Standard administrator.
- SSH public-key authentication only.
- Sudo access with password.

backupsvc:
- Dedicated rsync backup account.
- SSH public-key authentication.
- No usable password.
- Must remain functional after SSH changes.

chinook:
- Legacy UID 0 account.
- Password locked, account expired, shell disabled.
- Do not delete before reviewing dependencies.

SSH:
- Standard port 22.
- Debian's original sshd_config.
- Git-managed security drop-in.
- No SSH password authentication.
- Restrict access using network firewall rules.

Automatic updates:
- Debian security updates only.
- Daily checks and installation.
- No automatic OS reboot.
- Review service restart behavior on critical servers.

# IMPORTANT

Before SSH changes:
1. Verify a NEW itadmin SSH key login.
2. Verify sudo.
3. Check backupsvc and other SSH-dependent services.
4. Keep the original SSH connection open.
5. Ensure console recovery access is available.

The SSH scripts have no timed automatic rollback.

Before disabling services:
Check dependencies, active connections and monitoring.

Before updating Debian:
Verify the backup first.

# EXCEL STATUS

For every server, record:

Security OK | Backup OK | Update OK

Use OK only when all checks in that stage have passed.
Use Pending or Issue otherwise.


