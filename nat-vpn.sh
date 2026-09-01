#!/bin/bash
# ==================================================
# NAT-VPN — Versi Aman (Tidak Bentrok dengan Lama)
# Ubuntu 22.04 / 24.04 LTS
# ==================================================
set -e

echo -e "\e[32m========================================\e[0m"
echo -e "\e[32m    NAT-VPN TANPA BENTROK ✅           \e[0m"
echo -e "\e[32m========================================\e[0m"

# --------------------------
# 1. UPDATE & INSTALL PAKET TAMBAHAN
# --------------------------
echo -e "\n\e[34m[1/5] Update & install paket tambahan...\e[0m"
apt update -y
apt install -y curl wget net-tools iptables iptables-persistent gnupg2

# --------------------------
# 2. AKTIFKAN IP FORWARDING (WAJIB AGAR INTERNET LEWAT)
# --------------------------
echo -e "\n\e[34m[2/5] Aktifkan IP Forwarding...\e[0m"
cat > /etc/sysctl.d/99-vpn-forward.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
EOF
sysctl -p /etc/sysctl.d/99-vpn-forward.conf

# --------------------------
# 3. KONFIGURASI NAT / MASQUERADE (AGAR INTERNET BERJALAN)
# --------------------------
echo -e "\n\e[34m[3/5] Set NAT & Firewall rules...\e[0m"
IFACE=$(ip route show default | awk '/default/ {print $5}')
iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 109 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 2080 -j ACCEPT  # Port baru Xray
iptables -A INPUT -p tcp --dport 2443 -j ACCEPT  # Port baru Xray TLS
netfilter-persistent save

# --------------------------
# 4. INSTALL XRAY DENGAN PORT BARU (TIDAK BENTROK!)
# --------------------------
echo -e "\n\e[34m[4/5] Install Xray VMess — Port 2080/2443...\e[0m"
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

UUID="68f67a52-2df2-4163-9829-3d6a69b992e4"
mkdir -p /usr/local/etc/xray

# Backup config lama kalau ada
[ -f /usr/local/etc/xray/config.json ] && cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.bak

# Config Xray dengan PORT BARU — TIDAK BENTROK!
cat > /usr/local/etc/xray/config.json <<EOF
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
                        "id": "$UUID",
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
        },
        {
            "port": 2443,
            "listen": "0.0.0.0",
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "alterId": 0,
                        "level": 8
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "security": "tls",
                "tlsSettings": {
                    "allowInsecure": true,
                    "certificates": [
                        {
                            "certificateFile": "/etc/ssl/certs/ssl-cert-snakeoil.pem",
                            "keyFile": "/etc/ssl/private/ssl-cert-snakeoil.key"
                        }
                    ]
                },
                "wsSettings": { "path": "/vmess" }
            }
        }
    ],
    "outbounds": [
        { "protocol": "freedom", "settings": {} }
    ]
}
EOF

systemctl restart xray
systemctl enable xray

# --------------------------
# 5. TAMPILKAN INFO
# --------------------------
IP=$(curl -s ifconfig.me)
echo -e "\n\e
