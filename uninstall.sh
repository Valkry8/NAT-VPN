#!/bin/bash
echo "⚠️  Menghapus semua instalasi VPN..."
systemctl stop dropbear haproxy v2ray udp-tunnel
systemctl disable dropbear haproxy v2ray udp-tunnel
rm -f /etc/systemd/system/udp-tunnel.service
rm -rf /usr/local/etc/v2ray
apt remove -y dropbear haproxy v2ray
apt autoremove -y
echo "✅ Selesai dihapus!"

