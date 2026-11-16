
#!/usr/bin/env bash
set -euo pipefail

# Dedicated Debian rsync backup account.
#
# --status  Read-only security audit.
# --apply   Create or standardize backupsvc.
#
# The approved SSH public key is managed here.
# Never store the private key on this server.

ACCOUNT="backupsvc"
HOME_DIR="/home/backupsvc"
SSH_DIR="$HOME_DIR/.ssh"
KEY_FILE="$SSH_DIR/authorized_keys"
SUDO_FILE="/etc/sudoers.d/backupsvc"

# Approved public key from backup-debian.
PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDP29D9Xk+FDve5kLSh+wJQrlA6LuYFOjjaVz1DyG4j9 backupsvc@backup-debian'

# Disable forwarding, PTY and SSH user RC.
EXPECTED_KEY="restrict $PUBLIC_KEY"

# Exact observed rsync backup command.
SUDO_RULE='backupsvc ALL=(root) NOPASSWD: /usr/bin/rsync --server --sender -lHogDtpAXre.iLsfxCIvu --ignore-missing-args --numeric-ids . /'

die() {
    echo "ERROR: $*" >&2
    exit 1
}

warn() {
    echo "WARNING: $*"
}

[[ $EUID -eq 0 ]] || die "Run as root."

case "${1:-}" in
    --status|--apply)
        MODE="$1"
        [[ $# -eq 1 ]] || die "Unexpected arguments."
        ;;
    *)
        echo "Usage: $0 --status | --apply"
        exit 2
        ;;
esac

account_exists() {
    getent passwd "$ACCOUNT" >/dev/null
}

check_required_tools() {
    for tool in getent id passwd chage ssh-keygen \
                sshd visudo sudo stat; do
        command -v "$tool" >/dev/null ||
            die "Missing command: $tool"
    done
}

check_key() {
    echo
    echo "=== SSH PUBLIC KEY ==="

    if [[ ! -f "$KEY_FILE" ||
          -L "$KEY_FILE" ]]; then
        warn "authorized_keys is missing or invalid."
        return
    fi

    echo "Installed key fingerprint:"
    ssh-keygen -lf "$KEY_FILE" -E sha256 ||
        warn "Unable to read public key fingerprint."

    if [[ "$(cat "$KEY_FILE")" == "$EXPECTED_KEY" ]]; then
        echo "AUTHORIZED KEY: OK"
        echo "Only the approved Ed25519 key is installed."
    else
        warn "AUTHORIZED KEY: OUTDATED OR UNEXPECTED"
        echo "The key file differs from the approved policy."
        echo "Run --apply to replace its contents."
    fi

    local uid
    uid=$(id -u "$ACCOUNT")

    if [[ "$(stat -c '%u:%a' "$SSH_DIR")" \
          != "$uid:700" ]]; then
        warn "Incorrect .ssh ownership or permissions."
    else
        echo "SSH DIRECTORY: OK"
    fi

    if [[ "$(stat -c '%u:%a' "$KEY_FILE")" \
          != "$uid:600" ]]; then
        warn "Incorrect authorized_keys permissions."
    else
        echo "AUTHORIZED_KEYS PERMISSIONS: OK"
    fi
}

check_account() {
    echo "=== BACKUP SERVICE ACCOUNT ==="

    if ! account_exists; then
        warn "backupsvc does not exist."
        echo "Run --apply to create the account."
        return
    fi

    id "$ACCOUNT"

    local uid gid shell status expiry home
    uid=$(id -u "$ACCOUNT")
    gid=$(id -g "$ACCOUNT")
    shell=$(getent passwd "$ACCOUNT" | cut -d: -f7)
    home=$(getent passwd "$ACCOUNT" | cut -d: -f6)
    status=$(passwd -S "$ACCOUNT" | awk '{print $2}')
    expiry=$(getent shadow "$ACCOUNT" | cut -d: -f8)

    echo "Home: $home"
    echo "Shell: $shell"
    echo "Password status: $status"

    [[ "$uid" -ne 0 ]] ||
        warn "backupsvc has UID 0!"

    [[ "$gid" -ne 0 ]] ||
        warn "backupsvc has GID 0!"

    [[ "$home" == "$HOME_DIR" ]] ||
        warn "Unexpected home directory."

    [[ "$status" == L ]] ||
        warn "Password is not locked."

    if [[ -n "$expiry" ]] &&
       [[ "$expiry" -le "$(($(date +%s) / 86400))" ]]; then
        warn "Account is expired."
    fi

    if id -nG "$ACCOUNT" |
       tr ' ' '\n' | grep -Fxq sudo; then
        warn "backupsvc belongs to the sudo group."
    fi

    check_key
}

check_sshd() {
    echo
    echo "=== EFFECTIVE SSH AUTHENTICATION ==="

    local config
    config=$(
        sshd -T \
            -C user=backupsvc,host=localhost,addr=127.0.0.1
    ) || {
        warn "Unable to inspect effective SSH policy."
        return
    }

    echo "$config" | grep -E \
        '^(authenticationmethods|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|authorizedkeysfile|authorizedkeyscommand|trustedusercakeys|hostbasedauthentication|gssapiauthentication) '

    local key_files key_command ca
    key_files=$(
        echo "$config" |
        awk '$1=="authorizedkeysfile" {
            $1=""; sub(/^ /,""); print
        }'
    )

    key_command=$(
        echo "$config" |
        awk '$1=="authorizedkeyscommand" {print $2}'
    )

    ca=$(
        echo "$config" |
        awk '$1=="trustedusercakeys" {print $2}'
    )

    if [[ "$key_files" != ".ssh/authorized_keys" ]]; then
        warn "Other SSH authorized-key paths may be enabled."
    fi

    if [[ "$key_command" != none ]]; then
        warn "External SSH key provider is configured."
    fi

    if [[ "$ca" != none ]]; then
        warn "SSH certificate authority is configured."
    fi

    if ! echo "$config" |
         grep -Fxq 'authenticationmethods publickey'; then
        warn "SSH is not explicitly limited to publickey."
    fi

    if ! echo "$config" |
         grep -Fxq 'passwordauthentication no'; then
        warn "SSH password authentication may be enabled."
    fi

    if ! echo "$config" |
         grep -Fxq 'kbdinteractiveauthentication no'; then
        warn "Keyboard-interactive authentication may be enabled."
    fi
}

check_sudo() {
    echo
    echo "=== SUDOERS CONFIGURATION ==="

    if [[ ! -f "$SUDO_FILE" ||
          -L "$SUDO_FILE" ]]; then
        warn "Dedicated sudoers file missing or invalid."
    else
        stat -c '%U:%G %a %n' "$SUDO_FILE"

        if [[ "$(stat -c '%u:%g:%a' "$SUDO_FILE")" \
              != "0:0:440" ]]; then
            warn "Incorrect sudoers permissions."
        fi

        local installed
        installed=$(
            grep -E \
                '^[[:space:]]*backupsvc[[:space:]]' \
                "$SUDO_FILE" || true
        )

        if [[ "$installed" == "$SUDO_RULE" ]]; then
            echo "RSYNC SUDO RULE: OK"
        else
            warn "RSYNC SUDO RULE: DIFFERENT"
        fi
    fi

    echo
    visudo -c

    if account_exists; then
        echo
        echo "=== EFFECTIVE SUDO PERMISSIONS ==="
        sudo -l -U "$ACCOUNT"
        echo "Review any additional permissions above."
    fi
}

create_account() {
    if account_exists; then
        echo "BACKUPSVC: Already exists."
        return
    fi

    echo
    echo "=== CREATE BACKUP SERVICE ACCOUNT ==="

    if getent group "$ACCOUNT" >/dev/null; then
        die "Group backupsvc already exists; review manually."
    fi

    if [[ -e "$HOME_DIR" || -L "$HOME_DIR" ]]; then
        die "Home directory already exists; review manually."
    fi

    useradd \
        --create-home \
        --home-dir "$HOME_DIR" \
        --user-group \
        --shell /bin/sh \
        "$ACCOUNT"

    echo "BACKUPSVC: CREATED"
}

apply_account_policy() {
    echo
    echo "=== STANDARDIZE ACCOUNT ==="

    local uid gid home
    uid=$(id -u "$ACCOUNT")
    gid=$(id -g "$ACCOUNT")
    home=$(getent passwd "$ACCOUNT" | cut -d: -f6)

    [[ "$uid" -ne 0 ]] ||
        die "Refusing account with UID 0."

    [[ "$gid" -ne 0 ]] ||
        die "Refusing account with GID 0."

    [[ "$home" == "$HOME_DIR" ]] ||
        die "Unexpected home directory."

    if id -nG "$ACCOUNT" |
       tr ' ' '\n' | grep -Fxq sudo; then
        die "backupsvc belongs to sudo group. Review first."
    fi

    passwd -l "$ACCOUNT"

    # Account must remain usable for SSH public-key auth.
    chage -E -1 "$ACCOUNT"

    usermod --shell /bin/sh "$ACCOUNT"

    echo "PASSWORD: LOCKED"
    echo "ACCOUNT EXPIRATION: DISABLED"
    echo "SHELL: /bin/sh"
}

apply_ssh_key() {
    echo
    echo "=== STANDARDIZE SSH AUTHORIZED KEY ==="

    if [[ -L "$HOME_DIR" || -L "$SSH_DIR" ||
          -L "$KEY_FILE" ]]; then
        die "Symlink detected in backupsvc SSH path."
    fi

    [[ -d "$HOME_DIR" ]] ||
        die "Home directory missing."

    install -d \
        -o "$ACCOUNT" \
        -g "$(id -gn "$ACCOUNT")" \
        -m 0700 "$SSH_DIR"

    if [[ -e "$KEY_FILE" && ! -f "$KEY_FILE" ]]; then
        die "authorized_keys is not a regular file."
    fi

    if [[ -f "$KEY_FILE" ]]; then
        if [[ "$(cat "$KEY_FILE")" == "$EXPECTED_KEY" ]]; then
            chown "$ACCOUNT:$(id -gn "$ACCOUNT")" \
                "$KEY_FILE"
            chmod 0600 "$KEY_FILE"
            echo "SSH KEY: ALREADY CURRENT"
            return
        fi

        local backup
        backup=$(mktemp /root/backupsvc-old-keys.XXXXXXXX)
        cp -a "$KEY_FILE" "$backup"
        echo "Previous keys saved: $backup"
    fi

    local tmp
    tmp=$(mktemp "$SSH_DIR/.authorized_keys.XXXXXXXX")

    printf '%s\n' "$EXPECTED_KEY" > "$tmp"

    chown "$ACCOUNT:$(id -gn "$ACCOUNT")" "$tmp"
    chmod 0600 "$tmp"

    mv -f "$tmp" "$KEY_FILE"

    echo "SSH KEY: INSTALLED"
    echo "All previous authorized_keys entries replaced."
}

apply_sudo() {
    echo
    echo "=== STANDARDIZE BACKUP SUDO ==="

    [[ -x /usr/bin/rsync ]] ||
        die "/usr/bin/rsync is not installed."

    [[ ! -L "$SUDO_FILE" ]] ||
        die "Refusing sudoers symlink."

    if [[ -e "$SUDO_FILE" && ! -f "$SUDO_FILE" ]]; then
        die "Invalid sudoers target."
    fi

    visudo -c ||
        die "Existing sudo configuration is invalid."

    local tmp backup="" had_original=0
    tmp=$(mktemp /etc/sudoers.d/.backupsvc.XXXXXXXX)

    printf '%s\n' \
        '# Backup service account' \
        '# Exact root rsync sender command' \
        '' \
        "$SUDO_RULE" > "$tmp"

    chown root:root "$tmp"
    chmod 0440 "$tmp"

    if ! visudo -cf "$tmp"; then
        rm -f "$tmp"
        die "Generated sudoers configuration is invalid."
    fi

    if [[ -f "$SUDO_FILE" ]]; then
        had_original=1
        backup=$(mktemp /root/backupsvc-sudo.XXXXXXXX)
        cp -a "$SUDO_FILE" "$backup"
    fi

    mv -f "$tmp" "$SUDO_FILE"

    if ! visudo -c; then
        echo "ERROR: Restoring previous sudoers configuration."

        if [[ "$had_original" -eq 1 ]]; then
            cp -a "$backup" "$SUDO_FILE"
        else
            rm -f "$SUDO_FILE"
        fi

        die "Sudoers validation failed."
    fi

    echo "SUDOERS: INSTALLED"
}

check_required_tools

case "$MODE" in
    --status)
        check_account
        check_sshd
        check_sudo
        ;;

    --apply)
        [[ -x /usr/bin/rsync ]] ||
            die "/usr/bin/rsync is not installed."

        visudo -c ||
            die "Existing sudo configuration is invalid."

        # Confirm the approved public key is syntactically valid.
        tmpkey=$(mktemp)
        printf '%s\n' "$PUBLIC_KEY" > "$tmpkey"

        if ! ssh-keygen -lf "$tmpkey" -E sha256; then
            rm -f "$tmpkey"
            die "Approved public key is invalid."
        fi
        rm -f "$tmpkey"

        create_account
        apply_account_policy
        apply_ssh_key
        apply_sudo

        echo
        echo "=== FINAL AUDIT ==="
        check_account
        check_sshd
        check_sudo
        ;;
esac

echo
echo "BACKUP SERVICE ACCOUNT CHECK COMPLETED"

