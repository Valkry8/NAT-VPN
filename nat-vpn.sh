#!/bin/bash
# ==================================================
# NAT-VPN — Server Setup Script
# Ubuntu 22.04 / 24.04 LTS
# Fitur: IP Forward + NAT + Xray VMess (Port 2080)
# Repository: https://github.com/Valkry8/NAT-VPN
# ==================================================
set -e

echo -e "\e[32m========================================\e[0m"
echo -e "\e[32m        NAT-VPN INSTALLER              \e[0m"
echo -e "\e[32m========================================\e[0m"

# --------------------------
# 1. UPDATE SISTEM
# --------------------------
echo -e "\n\e[34m[1/5] Update sistem...\e[0m"
apt update -y
apt install -y curl wget net-tools iptables iptables-persistent gnupg2

# --------------------------
# 2. AKTIFKAN IP FORWARDING
# --------------------------
echo -e "\n\e[34m[2/5] Aktifkan IP Forwarding...\e[0m"
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-vpn-forward.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.d/99-vpn-forward.conf
echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.d/99-vpn-forward.conf
echo "net.ipv4.tcp_tw_reuse = 1" >> /etc/sysctl.d/99-vpn-forward.conf
echo "net.ipv4.tcp_fin_timeout = 30" >> /etc/sysctl.d/99-vpn-forward.conf
sysctl -p /etc/sysctl.d/99-vpn-forward.conf

# --------------------------
# 3. NAT & FIREWALL
# --------------------------
echo -e "\n\e[34m[3/5] Set NAT & Firewall rules...\e[0m"
IFACE=$(ip route show default | awk '/default/ {print $5}')
iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 109 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 2080 -j ACCEPT
netfilter-persistent save

# --------------------------
# 4. KONFIGURASI XRAY VMess
# --------------------------
echo -e "\n\e[34m[4/5] Konfigurasi Xray VMess...\e[0m"
UUID="68f67a52-2df2-4163-9829-3d6a69b992e4"
mkdir -p /usr/local/etc/xray

# Backup config lama
[ -f /usr/local/etc/xray/config.json ] && cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.bak

# Tulis config JSON langsung
cat > /usr/local/etc/xray/config.json << 'ENDJSON'
{
    "log": { "loglevel": "info" },
    "inbounds": [
        {
            "port": 2080,
            "listen": "0.0.0.0",
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "68f67a52-2df2-4163-9829-3d6a69b992e4",
                        "alterId": 0,
                        "level": 8
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": { "path": "/vmess" }
            }
        }
    ],
    "outbounds": [
        { "protocol": "freedom", "settings": {} }
    ]
}
ENDJSON

systemctl restart xray
systemctl enable xray

# --------------------------
# 5. TAMPILKAN INFO
# --------------------------
IP=$(curl -s ifconfig.me)
echo -e "\n\e
