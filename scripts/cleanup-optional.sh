#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }

case "${1:-}" in
    --status)
        echo '=== NFS mounts ==='
        findmnt -t nfs,nfs4 || true
        echo '=== NFS exports ==='
        command -v exportfs >/dev/null && exportfs -v || true
        echo '=== NFS/RPC/NRPE units ==='
        systemctl list-unit-files 'nfs*' 'rpcbind*' 'nagios-nrpe-server*' --no-pager
        echo '=== Legacy account ==='
        id chinook || true
        ;;
    --disable-nrpe)
        echo 'Ensure CheckMK or other replacement monitoring is working first.'
        read -r -p 'Type YES to disable NRPE: ' answer
        [[ "$answer" == YES ]] || exit 1
        systemctl disable --now nagios-nrpe-server.service
        ;;
    --expire-chinook)
        echo 'Verify this account is unused by services, backup jobs and automation.'
        read -r -p 'Type YES to expire chinook: ' answer
        [[ "$answer" == YES ]] || exit 1
        usermod --expiredate 1 chinook
        ;;
    *)
        echo "Usage: $0 --status | --disable-nrpe | --expire-chinook"
        echo 'NFS/RPC changes must be reviewed per server role; none are automated.'
        exit 2
        ;;
esac
