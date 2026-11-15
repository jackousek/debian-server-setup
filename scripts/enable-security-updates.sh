
#!/usr/bin/env bash
set -euo pipefail

# Enable automatic Debian security updates.
# Run as root.

[[ $EUID -eq 0 ]] || {
    echo "Run as root."
    exit 1
}

. /etc/os-release

[[ "$ID" == "debian" ]] || {
    echo "ERROR: This script supports Debian only."
    exit 1
}

echo "=== INSTALL ==="

apt-get update
apt-get install -y unattended-upgrades

echo "=== DAILY UPDATES ==="

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "=== SECURITY UPDATES ONLY ==="

cat > /etc/apt/apt.conf.d/52unattended-upgrades-local <<'EOF'
#clear Unattended-Upgrade::Origins-Pattern;
#clear Unattended-Upgrade::Allowed-Origins;

Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};

Unattended-Upgrade::Automatic-Reboot "false";
EOF

echo "=== ENABLE APT TIMERS ==="

systemctl enable --now \
    apt-daily.timer \
    apt-daily-upgrade.timer

echo "=== VERIFY CONFIGURATION ==="

apt-config dump | grep -E \
    'APT::Periodic|Unattended-Upgrade::Origins-Pattern|Unattended-Upgrade::Allowed-Origins|Unattended-Upgrade::Automatic-Reboot'

systemctl list-timers 'apt-daily*' --no-pager

echo "=== TEST ==="

unattended-upgrade --dry-run --verbose

echo
echo "Review the allowed origins and dry-run output."
echo "Security updates configured. Automatic reboot disabled."

