
# Debian Server Setup

Standard setup, security and maintenance for Debian servers.

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
configures sudo, and copies SSH authorized keys
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
- Replaces the main SSH configuration with the reference.
- Installs our Git-managed security policy.
- Validates SSH syntax and effective settings.
- Reloads SSH and checks that the service is active.

IMPORTANT:
The reference configuration is not guaranteed to match
the package-maintained conffile checksum. Package upgrade
prompts may still occur.

Test a NEW itadmin SSH login immediately.
Verify backupsvc access from the backup server.

### Step 3 — User security audit

Read-only audit:

```bash
bash scripts/user-audit.sh --status
```

Automatically disable chinook:

```bash
bash scripts/user-audit.sh --apply
```


The user audit script:
- Lists UID 0 accounts and usable passwords.
- Reports chinook UID and sudo privileges.
- Locks and expires chinook.
- Disables chinook's shell.
- Assigns a free UID if chinook has UID 0.
- Removes chinook from the sudo group.
- Verifies the final configuration.
- Preserves root, itadmin and backupsvc.

For shared UID 0 accounts, root-owned files
are not automatically changed.

Review direct sudo rules and server dependencies.
Test on one server before wider deployment.

### Step 4 — Disable unused services

Check current status:

```bash
bash scripts/cleanup-optional.sh --status
```

Disable unused NFS, RPC and NRPE services:

```bash
bash scripts/cleanup-optional.sh --apply
```

The script targets:
- nfs-server
- nfs-kernel-server
- nfs-common
- nfs-blkmap
- nfs-idmapd
- nfs-utils
- nfs-client
- rpcbind
- rpc-statd
- rpc-gssd
- rpc-svcgssd
- fsidd
- nagios-nrpe-server

The script:
- Checks for active NFS mounts.
- Checks NFS entries in /etc/fstab.
- Checks configured NFS exports.
- Stops if these dependencies are detected.
- Stops and disables matching systemd units.
- Masks them to prevent future activation.
- Verifies the final unit states.

IMPORTANT:
Do not run --apply on servers requiring NFS,
RPC or NRPE. Masking prevents service activation.

Check network listeners:

```bash
ss -lntup
```

Verify CheckMK and important applications.

The script does not uninstall packages
or modify user accounts.

#Postfix ETH
cp -a /etc/postfix/main.cf /etc/postfix/main.cf.bak

postconf -e 'inet_interfaces = loopback-only'
postfix check
systemctl restart postfix



### Step 5 — Automatic security updates

```bash
bash scripts/enable-security-updates.sh
```

Target configuration:
- Debian security updates only.
- Daily checks and installation.
- No automatic OS reboot.

Review allowed repositories and the dry-run result.

Check timers:

```bash
systemctl list-timers 'apt-daily*'
```

Review automatic service restart behavior,
especially on production database servers.

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
- [ ] Unnecessary NFS/RPC/NRPE services disabled
- [ ] Automatic security updates configured
- [ ] CheckMK monitoring works
- [ ] Firewall access reviewed

SECURITY OK — All checks passed.

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

This verifies one file transfer, not the
completeness or recoverability of the entire backup.

BACKUP OK — Test file transferred and alerts checked.

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

This is a normal package upgrade, not
a major Debian release upgrade.

### Step 3 — Check reboot requirement

```bash
test -f /run/reboot-required && cat /run/reboot-required
```

Reboot during a maintenance window if required.

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
ln -s ~/dotfiles/tmux/.tmux.conf ~/.tmux.conf

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

Keep the original session open.
Verify a new SSH connection afterward.

---

# SCRIPT REFERENCE

| Script | Purpose |
|---|---|
| bootstrap.sh | Create itadmin and configure administration |
| standardize-ssh.sh | Restore Debian SSH defaults and apply policy |
| apply-ssh-hardening.sh | Update the SSH security drop-in |
| user-audit.sh | Audit accounts and disable chinook |
| cleanup-optional.sh | Disable unused NFS/RPC/NRPE services |
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
- Standard SSH port 22.

Restrict SSH access using network firewall rules.

IMPORTANT:
Keep the original SSH session open during changes.
SSH scripts do not provide timed automatic rollback.

# AUTOMATIC SECURITY UPDATES

- Debian security updates only.
- Daily checks and installation.
- No automatic OS reboot.
- Verify apt timers and allowed origins.
- Check critical application restart behavior.

# EXCEL TRACKING

Track every server using three columns:

Security | Backup | Update

Status:
- Pending
- OK
- Issue

Mark OK only when all required checks have passed.


