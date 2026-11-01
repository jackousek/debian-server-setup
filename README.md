# Debian Server Setup

Bash scripts for initial Debian server configuration.

## Installation

Run as **root** on the target server.

### 1. Clone repository

```bash
apt update && apt install -y git
mkdir -p /root/git
cd /root/git
git clone git@github.com:jackousek/debian-server-setup.git
cd debian-server-setup
```

The private repository requires GitHub SSH access (preferably a read-only Deploy Key).

### 2. Configure server

```bash
bash scripts/bootstrap.sh
```

Installs Git, Vim, tmux and SSH, creates `itadmin`, configures sudo and SSH keys, and installs [dotfiles](https://github.com/jackousek/dotfiles).

### 3. Verify administrator access

Open a **new terminal**:

```bash
ssh itadmin@SERVER_IP
sudo -v
```

Keep the original root session open.

### 4. Apply SSH hardening

Run from the original root session:

```bash
bash scripts/apply-ssh-hardening.sh
```

Disables root SSH login and password authentication. Requires SSH public keys.

**Important:** Test a new SSH connection immediately. The script does not provide automatic rollback after an authentication lockout.

### 5. Optional cleanup

```bash
bash scripts/cleanup-optional.sh --status
```

Additional commands:

```bash
bash scripts/cleanup-optional.sh --disable-nrpe
bash scripts/cleanup-optional.sh --expire-chinook
```

Run only after verifying that the services or account are no longer needed.

## Updates

Update server scripts:

```bash
cd /root/git/debian-server-setup
git pull --ff-only
```

Update dotfiles as `itadmin`:

```bash
cd ~/dotfiles
git pull --ff-only
```

## Repository structure

```text
debian-server-setup/
├── README.md
├── scripts/
│   ├── bootstrap.sh
│   ├── apply-ssh-hardening.sh
│   └── cleanup-optional.sh
└── ssh/
    └── 01-admin-hardening.conf
```

## Security

- Run installation scripts as root.
- Use `itadmin` for regular administration.
- Never store passwords or private SSH keys in Git.
- Verify SSH and sudo before applying hardening.
- Keep console recovery access available during SSH changes.
