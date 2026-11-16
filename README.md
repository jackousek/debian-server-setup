
# Debian Server Setup

Standardized onboarding, security hardening, backup verification, and maintenance for Debian servers.

Repository: https://github.com/jackousek/debian-server-setup

> **Operating rules**
> - Run commands as `root` unless a section explicitly says **itadmin**.
> - Test changes on one server before wider deployment.
> - Keep a working `itadmin` SSH session and console recovery available during SSH and account changes.
> - Do not mark a check **OK** until the required verification succeeds.
> - Preserve server-specific configuration and application dependencies. A script's successful exit does not replace an operational check.

## 1. Get or update the repository

### 1.1 New server

```bash
apt update && apt install -y git
mkdir -p /root/git
cd /root/git
git clone https://github.com/jackousek/debian-server-setup.git
cd debian-server-setup
```

### 1.2 Existing server

```bash
cd /root/git/debian-server-setup
git pull --ff-only
```

All subsequent `scripts/...` commands assume the working directory is `/root/git/debian-server-setup`.

## 2. Security

Perform these steps in order. Record the outcome under **SSH**, **Security Audit**, and **Security Updates** in the server inventory.

### 2.1 Bootstrap administrator account

```bash
bash scripts/bootstrap.sh
```

The script installs administration packages, creates/configures `itadmin`, configures sudo, and copies SSH authorized keys where appropriate.

**Verify in a separate new SSH session as `itadmin`:**

```bash
id
sudo -v
```

Keep the original session open until SSH changes have been verified.

### 2.2 Standardize and harden SSH

**Before applying:**
- Verify `itadmin` SSH key authentication and sudo.
- Review SSH access for backup and other service accounts.
- Check for custom ports, `Match` blocks, forwarding requirements, and existing access restrictions.
- Ensure a recovery path exists.

```bash
bash scripts/standardize-ssh.sh
```

The script backs up the main SSH configuration, compares it with the Debian reference, installs the repository-managed policy, validates SSH, and reloads the service.

**Verify:**

```bash
sshd -t
systemctl is-active ssh
```

Open a **new** SSH session as `itadmin`. If `backupsvc` exists, verify its actual backup SSH access from the backup server before marking SSH **OK**.

> **Note:** Restoring a Debian reference configuration does not necessarily restore the package-managed conffile checksum; future package upgrades may still prompt about the SSH configuration. Changes are not protected by a timed automatic rollback.

### 2.3 Audit users and retire `chinook`

Read-only report:

```bash
bash scripts/user-audit.sh --status
```

Apply the legacy-account cleanup:

```bash
bash scripts/user-audit.sh --apply
```

The audit reports UID 0 accounts, usable passwords, login shells, SSH keys, sudo group membership, and the `chinook` account. The apply operation is intended to lock/expire `chinook`, set a non-login shell, remove sudo membership, and migrate a duplicate UID 0 entry to a free UID when present.

- `chinook` may not exist; absence is not an error.
- `backupsvc` may not exist; absence must be **reported as a warning**, not silently ignored or automatically created.
- `root`, `itadmin`, and `backupsvc` must not be modified by the legacy-account cleanup.
- A former UID 0 account's files are indistinguishable by UID from root-owned files; **do not recursively chown UID 0 files**.
- Review direct sudoers rules, active sessions, account-related jobs, and the final output.

**Verify:**

```bash
getent passwd | awk -F: '$3 == 0'
getent passwd chinook || true
id chinook 2>/dev/null || true
passwd -S chinook 2>/dev/null || true
```

Only `root` should normally retain UID 0. For a system where `chinook` previously had UID 0, verify a tested backup and console access **before** applying its account migration. If the script reports an error, stop and investigate; do not repeatedly rerun it without checking what changed.

### 2.4 Audit and standardize backup sudo permissions

This step applies only where the dedicated `backupsvc` account is used. It must not create `backupsvc` on other servers.

Audit:

```bash
bash scripts/backup-sudo.sh --status
```

Standardize after reviewing the existing permissions and confirming the actual backup command matches:

```bash
bash
bash scripts/backup-sudo.sh --apply
```

Required sudoers configuration at `/etc/sudoers.d/backupsvc`:

```sudoers
# Backup service account
# Allow only the observed rsync backup command
backupsvc ALL=(root) NOPASSWD: /usr/bin/rsync --server --sender -lHogDtpAXre.iLsfxCIvu --ignore-missing-args --numeric-ids . /
```

Required owner and mode: `root:root`, `0440`.

**Verify:**

```bash
visudo -c
stat -c '%U:%G %a %n' /etc/sudoers.d/backupsvc
sudo -l -U backupsvc
```

Verify that no other sudoers or group rules grant `backupsvc` broader privileges. The rule gives root-level read access through rsync; its SSH key and the backup server must be protected accordingly. If the account is absent, record the warning and confirm how that server is backed up. After any change, verify a real backup job.

> **Security:** A fixed rsync command is narrower than `NOPASSWD: ALL`, but it is still highly privileged. Never replace the exact arguments with a wildcard to work around a failing backup.

### 2.5 Disable unnecessary NFS, RPC, and legacy NRPE services

Read-only status:

```bash
bash scripts/cleanup-optional.sh --status
```

Apply **only after confirming the server does not use NFS, RPC-dependent applications, or NRPE**:

```bash
bash scripts/cleanup-optional.sh --apply
```

The script checks active NFS mounts, `/etc/fstab` and exports, then stops/disables/masks known NFS, RPC and NRPE units. Masked services cannot start until explicitly unmasked.

**Verify:**

```bash
ss -lntup
systemctl --failed
```

Confirm CheckMK monitoring and server-specific applications remain functional. **CheckMK Agent Controller on TCP 6556 is not legacy NRPE on TCP 5666** and should be retained when used.

### 2.6 Restrict Postfix SMTP to localhost (where applicable)

Use this on servers that **send email but do not need to accept SMTP connections from other machines**. Keep the existing relay configuration. Skip this step if Postfix is not installed or the server is an SMTP relay, gateway, or receives email over the network.

Review first:

```bash
systemctl status postfix --no-pager
postconf -n | grep -E '^(inet_interfaces|inet_protocols|mynetworks|relayhost) '
```

Back up the configuration, restrict the listener, validate, then restart:

```bash
cp -a /etc/postfix/main.cf /etc/postfix/main.cf.bak
postconf -e 'inet_interfaces = loopback-only'
postfix check
systemctl restart postfix
```

**Verify:**

```bash
postconf -h inet_interfaces
ss -lntp | grep ':25 ' || true
postqueue -p
```

SMTP should listen only on `127.0.0.1:25` and/or `[::1]:25`, not on the Ethernet IP or wildcard addresses. Send a test email and verify delivery through the configured relay. Review deprecated Postfix settings separately; do not change TLS behavior merely to address an unrelated warning.

### 2.7 Enable automatic Debian security updates

```bash
bash scripts/enable-security-updates.sh
```

Target policy:
- Debian security updates only.
- Daily update checks and unattended installation.
- No automatic OS reboot.

Review configured origins and the script's dry-run/check results.

**Verify:**

```bash
systemctl list-timers 'apt-daily*'
```

Package upgrades can restart critical services even without rebooting. Verify database and application availability and monitor results.

### 2.8 Final security verification

- [ ] `itadmin` key-based SSH login and sudo work.
- [ ] Root SSH login and SSH password authentication are disabled.
- [ ] Service-account SSH access is verified where applicable.
- [ ] Users, UID 0 accounts, passwords, SSH keys, and sudo privileges have been audited.
- [ ] `chinook` is disabled if present; unexpected privileges have been investigated.
- [ ] `backupsvc` presence/absence is recorded and backup sudo is correct where used.
- [ ] Unnecessary NFS/RPC/NRPE services are disabled, without breaking applications.
- [ ] Postfix is localhost-only where appropriate, and test mail succeeds.
- [ ] Automatic security updates are configured and verified.
- [ ] CheckMK monitoring and firewall restrictions are verified.

**Security: OK only after all applicable checks pass.** Record exceptions in **Notes**.

## 3. Backup verification

### 3.1 Create backup marker

```bash
bash scripts/create-backup-test.sh
```

Creates `/root/backup-test.txt` containing the hostname and creation timestamp.

### 3.2 Verify the actual backup

After the next scheduled rsync backup:

- [ ] Find `backup-test.txt` on the backup server.
- [ ] Verify the hostname and timestamp.
- [ ] Confirm the backup includes `/root`.
- [ ] Check that backup failure notifications are functional.

This is a **spot check of one file**, not a complete backup-integrity test or a restore test.

Enter the verification date in **Backup Check** only after the transfer is confirmed.

## 4. Debian package updates

Do not start maintenance without confirming a usable backup and an appropriate maintenance window.

### 4.1 Review

```bash
cat /etc/os-release
uname -r
apt update
apt list --upgradable
apt-get -s upgrade
```

Read the planned package actions, including service restarts and held packages.

### 4.2 Apply normal package updates

```bash
apt upgrade
```

Confirm the package list before proceeding. This is **not** a major Debian release upgrade.

### 4.3 Check reboot requirements

```bash
if [ -f /run/reboot-required ]; then
    cat /run/reboot-required
else
    echo 'No reboot-required marker found'
fi
```

The marker may not be present on every Debian installation; assess kernel and service updates separately. Reboot only during an approved maintenance window.

### 4.4 Verify services

```bash
systemctl --failed
systemctl status ssh --no-pager
ss -lntup
```

Check the server's databases, applications, monitoring, mail and backups. Enter the completion date in **Last Update** only after verification.

A Debian major-version upgrade requires its own procedure.

## 5. Additional administration commands

### 5.1 Install dotfiles — as `itadmin`

Log in as `itadmin` and run once:

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

### 5.2 Update dotfiles — as `itadmin`

```bash
git -C ~/dotfiles pull --ff-only
```

### 5.3 Update server scripts — as `root`

```bash
git -C /root/git/debian-server-setup pull --ff-only
```

### 5.4 Apply later SSH policy changes — as `root`

```bash
cd /root/git/debian-server-setup
bash scripts/apply-ssh-hardening.sh
```

Keep the current SSH session open and verify a new connection afterward.

### 5.5 Commit README or script changes — on Bastion

```bash
cd ~/git/debian-server-setup
git status
git diff --check

# When scripts change:
bash -n scripts/*.sh

git add README.md
git commit -m "Update Debian server setup documentation"
git push origin main
```

When changing scripts, stage the actual script files as well; do not assume that `git add README.md` includes them. Other servers can retrieve the committed changes using `git pull --ff-only`.

## 6. Script reference

| Script | Purpose |
|---|---|
| `bootstrap.sh` | Create/configure `itadmin` and administration tools |
| `standardize-ssh.sh` | Standardize SSH configuration and apply policy |
| `apply-ssh-hardening.sh` | Reapply SSH security policy changes |
| `user-audit.sh` | Audit accounts and retire `chinook` |
| `backup-sudo.sh` | Audit and standardize dedicated backup sudo permissions |
| `cleanup-optional.sh` | Stop and mask unused NFS/RPC/NRPE units |
| `enable-security-updates.sh` | Configure unattended Debian security updates |
| `create-backup-test.sh` | Create a timestamped backup verification file |

Script directory: `/root/git/debian-server-setup/scripts/`.

> The Postfix step uses native `postconf`/`systemctl` commands; there is currently no dedicated Postfix script in this procedure.

## 7. Security policy reference

### 7.1 Accounts

| Account | Policy |
|---|---|
| `root` | UID 0; SSH login disabled; console recovery retained |
| `itadmin` | Dedicated administrator; SSH keys; password-protected sudo; member of `sudo` |
| `backupsvc` | Optional dedicated rsync account; SSH keys; no usable password; unexpired when used; narrowly scoped sudo |
| `chinook` | Optional retired account; locked, expired, non-login shell, no sudo; UID 0 migration requires special care |
| Other accounts | Audit individually; preserve required service identities and access |

Do not disable application service accounts or remove their files without verifying dependencies.

### 7.2 SSH

Managed files:

```text
/etc/ssh/sshd_config
/etc/ssh/sshd_config.d/01-admin-hardening.conf
```

Policy:
- Root SSH login disabled.
- SSH password and keyboard-interactive authentication disabled.
- Public-key authentication required.
- Agent and X11 forwarding disabled.
- TCP forwarding enabled only where required.
- Standard port 22 unless a justified exception exists.
- Restrict management sources at the network firewall.

### 7.3 Automatic security updates

Security repositories only, daily checks, no automatic OS reboot. Review service restarts and monitoring alerts.

### 7.4 Network listeners

- **SSH (22/TCP):** required but restricted to approved administration sources.
- **Postfix (25/TCP):** localhost only unless the server explicitly accepts SMTP from the network.
- **NTP (123/UDP):** leave existing `ntpd` configuration unchanged; retain required time synchronization and enforce network firewall policy.
- **CheckMK Agent Controller (6556/TCP):** permitted only from approved monitoring sources.
- **Legacy NRPE (5666/TCP), RPC (111), and NFS (2049):** disabled when unused.

## 8. Excel maintenance tracking

Use one row per server:

| Hostname | SSH | Security Audit | Security Updates | Backup Check | Last Update | Notes |
|---|---|---|---|---|---|---|
| `image-noswap` | Pending | Pending | Pending | — | — | Example only; verify actual results |

- **SSH:** `Pending`, `OK`, or `Issue`.
- **Security Audit:** `Pending`, `OK`, or `Issue`; includes user audit, backup sudo, optional services, Postfix where applicable, and security verification.
- **Security Updates:** `Pending`, `OK`, or `Issue` for automated security-update setup.
- **Backup Check:** Date of confirmed backup-marker transfer.
- **Last Update:** Date of completed and verified package maintenance.
- **Notes:** Exceptions, missing service accounts, unresolved problems, or follow-up actions.

An empty date means the action has not yet been verified. Do not treat a script returning successfully as automatic proof of the entire security or backup process.

