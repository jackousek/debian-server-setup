
# Debian Server Setup

Standard Debian server setup, security and maintenance.

Repository:
https://github.com/jackousek/debian-server-setup

# QUICK START — EVERY SERVER

Run as root unless stated otherwise.

## 1. Get scripts

New server:

```bash
apt update && apt install -y git
mkdir -p /root/git
cd /root/git
git clone https://github.com/jackousek/debian-server-setup.git
cd debian-server-setup
```

Existing server:

```bash
cd /root/git/debian-server-setup
git pull --ff-only
```

## 2. SECURITY

### Step 1 — Bootstrap

```bash
bash scripts/bootstrap.sh
```

Creates itadmin, installs administration packages,
configures sudo and copies SSH authorized keys
when appropriate.

Open a NEW SSH session as itadmin:

```bash
id
sudo -v
```

Verify SSH key authentication and sudo.
Keep the original root session open.

### Step 2 — SSH configuration

Before continuing:
- Verify itadmin key login and sudo.
- Check backupsvc and other SSH service accounts.
- Review custom SSH ports, Match rules and forwarding.
- Keep console recovery access available.

```bash
bash scripts/standardize-ssh.sh
```

The script:
- Backs up the existing SSH configuration.
- Displays differences from Debian's reference.
- Restores the Debian SSH reference configuration.
- Installs our Git-managed security policy.
- Validates the SSH configuration.
- Reloads SSH and checks the service.

Test a NEW itadmin SSH login immediately.

Verify backupsvc access from the backup server.

### Step 3 — User audit

Read-only audit:

```bash
bash scripts/user-audit.sh --status
```

Automatic chinook cleanup:

```bash
bash scripts/user-audit.sh --apply
```

The script:
- Lists UID 0 accounts.
- Lists accounts with usable passwords.
- Lists accounts with login shells.
- Lists SSH authorized_keys files.
- Lists sudo group membership.
- Reports whether chinook has UID 0.
- Reports whether chinook belongs to sudo.
- Locks chinook's password.
- Expires chinook's account.
- Disables chinook's login shell.
- Removes chinook from the sudo group.
- Verifies the changes.

No changes are made to root, itadmin or backupsvc.

If chinook has UID 0 or running processes,
the script stops for manual investigation.

Review unexpected accounts and direct sudo rules.

### Step 4 — Legacy services

```bash
bash scripts/cleanup-optional.sh --status
```

Check:
- nfs-server
- rpcbind
- nfs-blkmap
- fsidd
- nagios-nrpe-server

Also inspect network listeners:

```bash
ss -tulpen
```

Disable NRPE only if replacement monitoring works:

```bash
bash scripts/cleanup-optional.sh --disable-nrpe
```

NFS/RPC services require individual dependency review.
The script does not automatically disable them.

### Step 5 — Automatic security updates

```bash
bash scripts/enable-security-updates.sh
```

Target configuration:
- Debian security updates only.
- Daily checks and installation.
- No automatic OS reboot.

Review the script output and verify the effective
allowed repositories and dry-run result.

Check timers:

```bash
systemctl list-timers 'apt-daily*'
```

Review service restart behavior on critical servers.

### Step 6 — Final security verification

- [ ] itadmin SSH key login works
- [ ] itadmin sudo works
- [ ] Root SSH login disabled
- [ ] SSH password authentication disabled
- [ ] chinook login disabled
- [ ] chinook removed from sudo
- [ ] UID 0 accounts reviewed
- [ ] Other user passwords reviewed
- [ ] backupsvc SSH access works
- [ ] Unnecessary services reviewed
- [ ] Automatic security updates configured
- [ ] CheckMK monitoring works

SECURITY OK — All required checks passed.

---

## 3. BACKUP

### Step 1 — Generate test file

On the production server:

```bash
bash scripts/create-backup-test.sh
```

Creates:

```text
/root/backup-test.txt
```

The file contains the hostname and creation timestamp.

### Step 2 — Verify backup

After the next scheduled rsync backup:

- [ ] Locate backup-test.txt on the backup server
- [ ] Verify hostname
- [ ] Verify timestamp
- [ ] Confirm backup failure email notifications

The backup must include /root/.

This checks transfer of the test file, not
full backup consistency or restore capability.

BACKUP OK — File verified and notifications checked.

---

## 4. UPDATE

Do not update before verifying backups.

### Step 1 — Check system

```bash
cat /etc/os-release
uname -r
apt update
apt list --upgradable
apt-get -s upgrade
```

Review proposed package changes.

### Step 2 — Update packages

```bash
apt upgrade
```

Confirm package changes before installation.

This is a normal package upgrade, not a
major Debian release upgrade.

### Step 3 — Check reboot requirement

```bash
test -f /run/reboot-required && cat /run/reboot-required
```

If required, reboot during a maintenance window.

### Step 4 — Verify services

```bash
systemctl --failed
systemctl status ssh --no-pager
ss -tulpen
```

Also verify:
- Databases
- Applications
- CheckMK monitoring
- Backup service
- Any server-specific services

UPDATE OK — Updates completed and services verified.

Major Debian upgrades require a separate procedure.

---

# ADDITIONAL COMMANDS

## Install dotfiles — ITADMIN

Log in as itadmin.

Run once:

```bash
cd ~
git clone https://github.com/jackousek/dotfiles.git

[ ! -e ~/.vimrc ] && [ ! -L ~/.vimrc ] || mv ~/.vimrc ~/.vimrc.bak
[ ! -e ~/.tmux.conf ] && [ ! -L ~/.tmux.conf ] || mv ~/.tmux.conf ~/.tmux.conf.bak

ln -s ~/dotfiles/vim/.vimrc ~/.vimrc
ln -s ~/dotfiles/tmux/.tmux.conf

echo '[ -f "$HOME/dotfiles/bash/.bashrc" ] && . "$HOME/dotfiles/bash/.bashrc"' >> ~/.bashrc

source ~/.bashrc
```

## Update dotfiles — ITADMIN

```bash
git -C ~/dotfiles pull --ff-only
```

## Update scripts — ROOT

```bash
git -C /root/git/debian-server-setup pull --ff-only
```

## Update SSH policy — ROOT

Only when the SSH policy changes in Git:

```bash
cd /root/git/debian-server-setup
bash scripts/apply-ssh-hardening.sh
```

Verify a new SSH connection afterward.

---

# SCRIPT REFERENCE

| Script | Purpose |
|---|---|
| bootstrap.sh | Create itadmin, install administration packages |
| standardize-ssh.sh | Restore Debian SSH defaults and apply policy |
| apply-ssh-hardening.sh | Update SSH security drop-in |
| user-audit.sh | Audit accounts and disable chinook |
| cleanup-optional.sh | Check legacy services and disable NRPE |
| enable-security-updates.sh | Configure automatic security updates |
| create-backup-test.sh | Create timestamp file for backup test |

Scripts directory:

```text
/root/git/debian-server-setup/scripts/
```

# ACCOUNT SECURITY POLICY

## root

- Password retained for console recovery.
- SSH login disabled.
- UID 0.

## itadmin

- Dedicated administrator account.
- Password for sudo and console authentication.
- SSH public-key authentication only.
- Member of sudo group.

## backupsvc

- Dedicated rsync backup account.
- No usable password.
- SSH public-key authentication.
- Must remain active and unexpired.
- Never modified by user-audit.sh.

## chinook

- Legacy administrator account.
- UID may differ between servers.
- Password locked.
- Account expired.
- Login shell disabled.
- Removed from sudo group.
- Files retained.
- UID 0 or running processes require manual review.

## Other accounts

- Review usable passwords and login shells.
- Do not disable required application accounts.
- Do not automatically remove SSH keys or accounts.

# SSH SECURITY POLICY

Configuration:

```text
/etc/ssh/sshd_config
/etc/ssh/sshd_config.d/01-admin-hardening.conf
```

Standard policy:
- Root SSH login disabled.
- Password authentication disabled.
- SSH public-key authentication enabled.
- TCP forwarding permitted where required.
- Agent forwarding disabled.
- X11 forwarding disabled.
- Port 22 unless a server-specific exception exists.

Restrict SSH access using network firewall rules.

IMPORTANT:
Keep the original SSH session open during changes.
SSH scripts do not provide timed automatic rollback.

# EXCEL TRACKING

Track every server using three columns:

Security | Backup | Update

Status:
- Pending
- OK
- Issue

Mark OK only when all required checks have passed.

