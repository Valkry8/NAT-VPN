#!/bin/bash
# VPN Ultimate — Uninstaller

set -e

echo -e "\e[1;31m⚠️  Menghapus VPN Ultimate...\e[0m"

# Stop semua service
systemctl stop --now dropbear haproxy xray udp-tunnel slowdns slowdns-alt 2>/dev/null || true
systemctl disable --now dropbear haproxy xray udp-tunnel slowdns slowdns-alt 2>/dev/null || true

# Hapus file service
rm -f /etc/systemd/system/udp-tunnel.service
rm -f /etc/systemd/system/slowdns.service
rm -f /etc/systemd/system/slowdns-alt.service

# Reload systemd
systemctl daemon-reload

# Hapus binary & config
rm -rf /usr/local/bin/udp-tunnel.py
rm -rf /usr/local/bin/slowdns-server
rm -rf /usr/local/etc/xray
rm -rf /etc/haproxy/certs
rm -rf /etc/vpn-ultimate
rm -rf /var/log/xray

# Hapus paket (opsional)
read -p "Hapus paket dependensi? (dropbear, haproxy, xray) (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    apt remove -y dropbear haproxy
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove 2>/dev/null
fi

# Reset Firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw --force enable

echo -e "\e[1;32m✅ VPN Ultimate berhasil dihapus!\e[0m"

