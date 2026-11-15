
#!/usr/bin/env bash
set -euo pipefail

# Disable unused NFS, RPC and NRPE services on Debian.
# Run as root. Safe to execute repeatedly.

[[ $EUID -eq 0 ]] || {
    echo "ERROR: Run as root."
    exit 1
}

UNITS=(
    nfs-server.service
    nfs-kernel-server.service
    nfs-common.service
    nfs-client.target
    nfs-blkmap.service
    nfs-idmapd.service
    nfs-utils.service
    rpcbind.service
    rpcbind.socket
    rpcbind.target
    rpc-statd.service
    rpc-statd-notify.service
    rpc-gssd.service
    rpc-svcgssd.service
    rpc-svcgssd.socket
    fsidd.service
    nagios-nrpe-server.service
)

unit_exists() {
    local state
    state=$(systemctl show "$1" -p LoadState --value)
    [[ "$state" != "not-found" ]]
}

status() {
    echo "=== NFS MOUNTS ==="
    findmnt -t nfs,nfs4 || true

    echo
    echo "=== NFS EXPORTS ==="
    if command -v exportfs >/dev/null; then
        exportfs -v || true
    fi

    echo
    echo "=== SERVICE STATUS ==="

    for unit in "${UNITS[@]}"; do
        if unit_exists "$unit"; then
            printf '%-32s active=%-10s enabled=%s\n' \
                "$unit" \
                "$(systemctl is-active "$unit" || true)" \
                "$(systemctl is-enabled "$unit" || true)"
        fi
    done

    echo
    echo "=== NETWORK LISTENERS ==="
    ss -lntup | grep -E \
        '(:111[[:space:]]|:2049[[:space:]]|:5666[[:space:]])' \
        || true
}

check_dependencies() {
    echo "=== CHECK NFS DEPENDENCIES ==="

    if findmnt -rn -t nfs,nfs4 | grep -q .; then
        echo "ERROR: Active NFS mounts detected."
        return 1
    fi

    if grep -Eq \
        '^[[:space:]]*[^#[:space:]].*[[:space:]]nfs4?[[:space:]]' \
        /etc/fstab; then
        echo "ERROR: NFS entries found in /etc/fstab."
        return 1
    fi

    if [[ -f /etc/exports ]] &&
       grep -Eq '^[[:space:]]*[^#[:space:]]' /etc/exports; then
        echo "ERROR: NFS exports configured."
        return 1
    fi

    if compgen -G '/etc/exports.d/*.exports' >/dev/null; then
        if grep -Eq '^[[:space:]]*[^#[:space:]]' \
            /etc/exports.d/*.exports; then
            echo "ERROR: NFS exports found in /etc/exports.d."
            return 1
        fi
    fi

    echo "No configured NFS mounts or exports detected."
}

apply() {
    check_dependencies

    echo
    echo "=== DISABLE SERVICES ==="

    for unit in "${UNITS[@]}"; do
        if ! unit_exists "$unit"; then
            continue
        fi

        echo "Processing: $unit"

        # Disable boot-time activation and stop the unit.
        if [[ "$(systemctl is-enabled "$unit" || true)" \
              == "enabled" ]]; then
            systemctl disable --now "$unit"
        fi

        # Prevent future activation, including socket activation.
        systemctl mask --now "$unit"
    done

    echo
    echo "=== VERIFICATION ==="

    local failed=0
    local state

    for unit in "${UNITS[@]}"; do
        if ! unit_exists "$unit"; then
            continue
        fi

        state=$(systemctl is-enabled "$unit" || true)

        if [[ "$state" != "masked" ]]; then
            echo "FAIL: $unit is not masked ($state)"
            failed=1
        elif systemctl is-active --quiet "$unit"; then
            echo "FAIL: $unit is still active"
            failed=1
        else
            echo "OK: $unit"
        fi
    done

    if [[ "$failed" -ne 0 ]]; then
        echo "ERROR: Some services require manual review."
        return 1
    fi

    echo
    echo "CLEANUP COMPLETED"
}

case "${1:-}" in
    --status)
        status
        ;;
    --apply)
        apply
        ;;
    *)
        echo "Usage: $0 --status | --apply"
        exit 2
        ;;
esac

