#!/bin/bash
# ==================================================
# NAT-VPN SERVER — Ubuntu 22.04 / 24.04 LTS
# Fitur: Dropbear SSH + Nginx WebSocket + Xray VMess + IP Forward + NAT
# Repository: https://github.com/Valkry8/NAT-VPN
# ==================================================

set -e

echo -e "\e[32m========================================\e[0m"
echo -e "\e[32m      NAT-VPN SERVER INSTALLER         \e[0m"
echo -e "\e[32m========================================\e[0m"

# --------------------------
# 1. UPDATE & INSTALL DEPENDENSI
# --------------------------
echo -e "\n\e[34m[1/8] Update sistem & install paket...\e[0m"
apt update -y && apt upgrade -y
apt install -y curl wget nano vim net-tools iptables iptables-persistent \
    build-essential libssl-dev zlib1g-dev lsb-release ca-certificates \
    software-properties-common gnupg2

# --------------------------
# 2. AKTIFKAN IP FORWARDING
# --------------------------
echo -e "\n\e[34m[2/8] Aktifkan IP Forwarding...\e[0m"
cat > /etc/sysctl.d/99-vpn-forward.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
EOF
sysctl -p /etc/sysctl.d/99-vpn-forward.conf

# --------------------------
# 3. KONFIGURASI NAT / MASQUERADE
# --------------------------
echo -e "\n\e[34m[3/8] Set NAT & Firewall rules...\e[0m"
IFACE=$(ip route show default | awk '/default/ {print $5}')
iptables -F
iptables -t nat -F
iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 109 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --dport 1194 -j ACCEPT
netfilter-persistent save

# --------------------------
# 4. INSTALL DROPBEAR SSH (Port 109)
# --------------------------
echo -e "\n\e[34m[4/8] Install Dropbear SSH Server...\e[0m"
apt install -y dropbear
mkdir -p /etc/dropbear
dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key

cat > /etc/default/dropbear <<EOF
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 109"
EOF

systemctl restart dropbear
systemctl enable dropbear

# --------------------------
# 5. INSTALL NGINX (WebSocket Proxy)
# --------------------------
echo -e "\n\e[34m[5/8] Install Nginx WebSocket Proxy...\e[0m"
apt install -y nginx

cat > /etc/nginx/sites-available/nat-vpn <<'EOF'
server {
    listen 80;
    listen 443 ssl http2;
    server_name _;

    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    location /vmess {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
EOF

ln -sf /etc/nginx/sites-available/nat-vpn /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx
systemctl enable nginx

# --------------------------
# 6. INSTALL XRAY VMess
# --------------------------
echo -e "\n\e[34m[6/8] Install Xray VMess + WebSocket...\e[0m"
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

UUID="68f67a52-2df2-4163-9829-3d6a69b992e4"
mkdir -p /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json <<EOF
{
    "log": { "loglevel": "info" },
    "inbounds": [
        {
            "port": 8080,
            "listen": "127.0.0.1",
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
# 7. BUAT AKUN SSH
# --------------------------
echo -e "\n\e[34m[7/8] Buat akun SSH...\e

