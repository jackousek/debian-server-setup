# Debian server bootstrap (no Ansible)

Copy `scripts/` and `ssh/` into `jackousek/dotfiles` on branch `master`.
This kit does not replace existing `bash/`, `vim/`, or `tmux/`.

## New Debian 12/13 server

As root:

```bash
apt-get update && apt-get install -y git
git clone https://github.com/jackousek/dotfiles.git /root/dotfiles
cd /root/dotfiles
bash scripts/bootstrap.sh
```

Open a **second** terminal and test `ssh itadmin@SERVER_IP` and `sudo -v`.
Inspect existing SSH drop-ins and key-dependent backup accounts before hardening.
Keep original SSH session open and have console access.

```bash
bash scripts/apply-ssh-hardening.sh
```

**Warning:** SSH script restores previous configuration on failed syntax/policy
checks, but has **no timed rollback** after a successful SSH reload. A successful
`sshd -t` does not guarantee that SSH authentication will work. Test a new
connection immediately and keep console access.

Optional, per-server operations:

```bash
bash scripts/cleanup-optional.sh --status
bash scripts/cleanup-optional.sh --disable-nrpe
bash scripts/cleanup-optional.sh --expire-chinook
```

NFS and RPC changes are intentionally not automated: determine dependencies
before shutting down services. Never commit passwords or private keys.

## Update personal settings

As `itadmin`:

```bash
cd ~/dotfiles && git pull --ff-only
```

System SSH files are **not** updated automatically with `git pull`.
