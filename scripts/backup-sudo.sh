
#!/usr/bin/env bash
set -euo pipefail

# Debian backup service account management
#
# --status : Read-only audit
# --apply  : Create or standardize backupsvc
#
# Managed configuration:
# - backupsvc account
# - SSH authorized_keys
# - SSH authorized_keys2 (remove if present)
# - Password authentication disabled for the account
# - Restricted sudo for rsync
#
# Does NOT modify sshd configuration.
#
# IMPORTANT:
# Before rotating keys on an existing server, verify
# that backup-debian uses the matching private key.

ACCOUNT="backupsvc"
HOME_DIR="/home/backupsvc"
SSH_DIR="$HOME_DIR/.ssh"
KEY_FILE="$SSH_DIR/authorized_keys"
LEGACY_KEY_FILE="$SSH_DIR/authorized_keys2"
SUDO_FILE="/etc/sudoers.d/backupsvc"

PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDP29D9Xk+FDve5kLSh+wJQrlA6LuYFOjjaVz1DyG4j9 backupsvc@backup-debian'

EXPECTED_KEY="restrict $PUBLIC_KEY"

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
        [[ $# -eq 1 ]] || die "Unexpected arguments."
        MODE="$1"
        ;;
    *)
        echo "Usage: $0 --status | --apply"
        exit 2
        ;;
esac

account_exists() {
    getent passwd "$ACCOUNT" >/dev/null
}

backup_file() {
    local source="$1"
    local name="$2"
    local dest

    dest=$(mktemp "/root/${name}.XXXXXXXX")
    cp -a "$source" "$dest"

    echo "Backup saved: $dest"
}

check_tools() {
    local tool

    for tool in \
        getent id passwd chage useradd usermod \
        ssh-keygen sshd visudo sudo stat \
        rsync install mktemp
    do
        command -v "$tool" >/dev/null ||
            die "Missing command: $tool"
    done
}

check_account() {
    echo
    echo "=== BACKUP SERVICE ACCOUNT ==="

    if ! account_exists; then
        warn "$ACCOUNT does not exist."
        echo "Run --apply to create the account."
        return
    fi

    id "$ACCOUNT"

    local uid gid home shell status expiry
    uid=$(id -u "$ACCOUNT")
    gid=$(id -g "$ACCOUNT")
    home=$(getent passwd "$ACCOUNT" | cut -d: -f6)
    shell=$(getent passwd "$ACCOUNT" | cut -d: -f7)
    status=$(passwd -S "$ACCOUNT" | awk '{print $2}')
    expiry=$(getent shadow "$ACCOUNT" | cut -d: -f8)

    echo "Home: $home"
    echo "Shell: $shell"
    echo "Password status: $status"

    [[ "$uid" -ne 0 ]] ||
        warn "backupsvc has UID 0!"

    [[ "$gid" -ne 0 ]] ||
        warn "backupsvc has primary GID 0!"

    [[ "$home" == "$HOME_DIR" ]] ||
        warn "Unexpected home directory."

    [[ "$status" == L ]] ||
        warn "Password is not locked."

    [[ "$shell" == /bin/sh ]] ||
        warn "Shell differs from standard /bin/sh."

    if [[ -n "$expiry" ]] &&
       [[ "$expiry" -le "$(($(date +%s) / 86400))" ]]; then
        warn "Account is expired."
    fi

    if id -nG "$ACCOUNT" |
       tr ' ' '\n' | grep -Fxq sudo; then
        warn "backupsvc belongs to sudo group."
    fi
}

check_ssh_keys() {
    echo
    echo "=== SSH AUTHORIZED KEYS ==="

    account_exists || return

    local uid
    uid=$(id -u "$ACCOUNT")

    if [[ ! -d "$SSH_DIR" || -L "$SSH_DIR" ]]; then
        warn ".ssh directory missing or invalid."
        return
    fi

    if [[ "$(stat -c '%u:%a' "$SSH_DIR")" \
          == "$uid:700" ]]; then
        echo "SSH DIRECTORY: OK"
    else
        warn "Incorrect .ssh ownership or permissions."
    fi

    if [[ ! -f "$KEY_FILE" || -L "$KEY_FILE" ]]; then
        warn "authorized_keys missing or invalid."
    else
        if [[ "$(stat -c '%u:%a' "$KEY_FILE")" \
              == "$uid:600" ]]; then
            echo "AUTHORIZED_KEYS PERMISSIONS: OK"
        else
            warn "Incorrect authorized_keys permissions."
        fi

        echo
        echo "Installed key fingerprint:"
        ssh-keygen -lf "$KEY_FILE" -E sha256 ||
            warn "Invalid SSH public key."

        echo
        if [[ "$(cat "$KEY_FILE")" == "$EXPECTED_KEY" ]]; then
            echo "AUTHORIZED KEY: OK"
            echo "Only the approved Ed25519 key is installed."
        else
            warn "AUTHORIZED KEY: OUTDATED OR UNEXPECTED"
            echo "Run --apply to replace existing keys."
        fi
    fi

    if [[ -e "$LEGACY_KEY_FILE" ||
          -L "$LEGACY_KEY_FILE" ]]; then
        warn "Additional SSH key file exists:"
        echo "$LEGACY_KEY_FILE"
    else
        echo "AUTHORIZED_KEYS2: NOT PRESENT"
    fi
}

check_ssh_policy() {
    echo
    echo "=== EFFECTIVE SSH AUTHENTICATION ==="

    local config
    config=$(
        sshd -T \
            -C user=backupsvc,host=localhost,addr=127.0.0.1
    ) || {
        warn "Cannot inspect effective SSH configuration."
        return 1
    }

    echo "$config" | grep -E \
        '^(authenticationmethods|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|authorizedkeysfile|authorizedkeyscommand|trustedusercakeys|hostbasedauthentication|gssapiauthentication) ' || true

    local value

    for setting in \
        pubkeyauthentication \
        passwordauthentication \
        kbdinteractiveauthentication \
        authenticationmethods \
        authorizedkeyscommand \
        trustedusercakeys \
        hostbasedauthentication \
        gssapiauthentication
    do
        value=$(awk -v key="$setting" \
            '$1==key {print $2}' <<< "$config")

        case "$setting:$value" in
            pubkeyauthentication:yes|\
            passwordauthentication:no|\
            kbdinteractiveauthentication:no|\
            authenticationmethods:publickey|\
            authorizedkeyscommand:none|\
            trustedusercakeys:none|\
            hostbasedauthentication:no|\
            gssapiauthentication:no)
                ;;
            *)
                warn "Unexpected SSH policy: $setting=$value"
                ;;
        esac
    done

    echo
    echo "NOTE: SSH configuration is never modified."
}

check_sudo() {
    echo
    echo "=== BACKUP SUDO CONFIGURATION ==="

    if [[ ! -f "$SUDO_FILE" ||
          -L "$SUDO_FILE" ]]; then
        warn "Sudoers file missing or invalid."
    else
        stat -c '%U:%G %a %n' "$SUDO_FILE"

        if [[ "$(stat -c '%u:%g:%a' "$SUDO_FILE")" \
              == "0:0:440" ]]; then
            echo "SUDOERS PERMISSIONS: OK"
        else
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
    echo "=== SUDO SYNTAX ==="

    visudo -c || warn "Sudo configuration validation failed."

    if account_exists; then
        echo
        echo "=== EFFECTIVE SUDO PERMISSIONS ==="
        sudo -l -U "$ACCOUNT" ||
            warn "Unable to list sudo permissions."

        echo
        echo "Review additional sudo permissions and groups."
    fi
}

create_account() {
    if account_exists; then
        echo "BACKUPSVC: Already exists."
        return
    fi

    echo
    echo "=== CREATE BACKUP SERVICE ACCOUNT ==="

    getent group "$ACCOUNT" >/dev/null &&
        die "Group backupsvc already exists."

    [[ ! -e "$HOME_DIR" && ! -L "$HOME_DIR" ]] ||
        die "Home directory already exists."

    useradd \
        --create-home \
        --home-dir "$HOME_DIR" \
        --user-group \
        --shell /bin/sh \
        "$ACCOUNT"

    echo "BACKUPSVC: CREATED"
}

apply_account() {
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
        die "backupsvc belongs to sudo group."
    fi

    passwd -l "$ACCOUNT"
    chage -E -1 "$ACCOUNT"
    usermod --shell /bin/sh "$ACCOUNT"

    echo "PASSWORD: LOCKED"
    echo "ACCOUNT EXPIRATION: DISABLED"
    echo "SHELL: /bin/sh"
}

apply_ssh_keys() {
    echo
    echo "=== STANDARDIZE SSH AUTHORIZED KEYS ==="

    if [[ -L "$HOME_DIR" || -L "$SSH_DIR" ||
          -L "$KEY_FILE" || -L "$LEGACY_KEY_FILE" ]]; then
        die "Symlink detected in SSH account paths."
    fi

    [[ -d "$HOME_DIR" ]] ||
        die "Home directory missing."

    [[ ! -e "$SSH_DIR" || -d "$SSH_DIR" ]] ||
        die "Invalid .ssh directory."

    [[ ! -e "$KEY_FILE" || -f "$KEY_FILE" ]] ||
        die "Invalid authorized_keys file."

    [[ ! -e "$LEGACY_KEY_FILE" ||
       -f "$LEGACY_KEY_FILE" ]] ||
        die "Invalid authorized_keys2 file."

    install -d \
        -o "$ACCOUNT" \
        -g "$(id -gn "$ACCOUNT")" \
        -m 0700 "$SSH_DIR"

    if [[ -f "$KEY_FILE" ]] &&
       [[ "$(cat "$KEY_FILE")" != "$EXPECTED_KEY" ]]; then
        backup_file "$KEY_FILE" "backupsvc-old-keys"
    fi

    if [[ -f "$LEGACY_KEY_FILE" ]]; then
        backup_file "$LEGACY_KEY_FILE" \
            "backupsvc-old-keys2"
    fi

    # Always install exactly one approved key.
    local tmp
    tmp=$(mktemp "$SSH_DIR/.authorized_keys.XXXXXXXX")

    printf '%s\n' "$EXPECTED_KEY" > "$tmp"

    chown "$ACCOUNT:$(id -gn "$ACCOUNT")" "$tmp"
    chmod 0600 "$tmp"

    mv -f "$tmp" "$KEY_FILE"

    # Remove additional default SSH key source.
    rm -f "$LEGACY_KEY_FILE"

    echo "AUTHORIZED KEY: INSTALLED"
    echo "AUTHORIZED_KEYS2: REMOVED IF PRESENT"
}

apply_sudo() {
    echo
    echo "=== STANDARDIZE BACKUP SUDO ==="

    [[ -x /usr/bin/rsync ]] ||
        die "/usr/bin/rsync is not installed."

    [[ ! -L "$SUDO_FILE" ]] ||
        die "Refusing sudoers symlink."

    [[ ! -e "$SUDO_FILE" || -f "$SUDO_FILE" ]] ||
        die "Invalid sudoers file."

    # Save existing sudoers before changing it.
    if [[ -f "$SUDO_FILE" ]]; then
        backup_file "$SUDO_FILE" "backupsvc-old-sudoers"

        # Repair known owner/mode problems first.
        chown root:root "$SUDO_FILE"
        chmod 0440 "$SUDO_FILE"
    fi

    # Other configuration errors still require investigation.
    visudo -c ||
        die "Existing sudo configuration has errors."

    local tmp
    tmp=$(mktemp /etc/sudoers.d/.backupsvc.XXXXXXXX)

    printf '%s\n' \
        '# Backup service account' \
        '# Allow only the observed rsync sender command' \
        '' \
        "$SUDO_RULE" > "$tmp"

    chown root:root "$tmp"
    chmod 0440 "$tmp"

    if ! visudo -cf "$tmp"; then
        rm -f "$tmp"
        die "Generated sudoers rule is invalid."
    fi

    mv -f "$tmp" "$SUDO_FILE"

    visudo -c ||
        die "Final sudoers validation failed."

    echo "SUDOERS: INSTALLED"
    echo "OWNER: root:root"
    echo "MODE: 0440"
}

check_approved_key() {
    local tmp
    tmp=$(mktemp)

    printf '%s\n' "$PUBLIC_KEY" > "$tmp"

    if ! ssh-keygen -lf "$tmp" -E sha256; then
        rm -f "$tmp"
        die "Approved Ed25519 key is invalid."
    fi

    rm -f "$tmp"
}

check_tools

case "$MODE" in
    --status)
        check_account
        check_ssh_keys
        check_ssh_policy
        check_sudo
        ;;

    --apply)
        echo "=== APPLY BACKUP SERVICE POLICY ==="

        check_approved_key

        # Check before making changes.
        [[ -x /usr/bin/rsync ]] ||
            die "/usr/bin/rsync is not installed."

        if [[ -L "$SUDO_FILE" ||
              ( -e "$SUDO_FILE" && ! -f "$SUDO_FILE" ) ]]; then
            die "Invalid sudoers target."
        fi

        # Repair the known sudoers permission issue before
        # account changes or SSH key rotation.
        apply_sudo_precheck_needed=0

        if [[ -f "$SUDO_FILE" ]]; then
            backup_file "$SUDO_FILE" \
                "backupsvc-sudoers-precheck"
            chown root:root "$SUDO_FILE"
            chmod 0440 "$SUDO_FILE"
        fi

        visudo -c ||
            die "Existing sudo configuration is invalid."

        create_account
        apply_account
        apply_sudo
        apply_ssh_keys

        echo
        echo "=== FINAL AUDIT ==="
        check_account
        check_ssh_keys
        check_ssh_policy
        check_sudo

        echo
        echo "BACKUP SERVICE POLICY APPLIED"
        ;;
esac

