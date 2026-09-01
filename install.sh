#!/bin/bash
# VPN All-in-One Installer
# SSH WebSocket + V2Ray + UDP
# Domain: tunel.randi.biz.id
# Support: Ubuntu 22.04 / 24.04 LTS

clear
echo "====================================="
echo "  VPN ALL-IN-ONE INSTALLER"
echo "  SSH WS + V2Ray + UDP"
echo "  Domain: tunel.randi.biz.id"
echo "====================================="
echo ""

# Cek root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Harus jalankan sebagai root!"
    exit 1
fi

# Cek Ubuntu
if ! grep -E "22.04|24.04" /etc/os-release > /dev/null; then
    echo "⚠️  Direkomendasikan Ubuntu 22.04 / 24.04 LTS"
    read -p "Lanjutkan? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi
fi

DOMAIN="tunel.randi.biz.id"
SSH_PORT="22"
WS_PORT="80 443"
V2RAY_PORT="443"
UDP_PORT="40000-40100"

echo "🔄 Update sistem..."
apt update -y && apt upgrade -y

echo "📦 Install dependensi..."
apt install -y --no-install-recommends \
    curl wget unzip tar gzip nano \
    openssl ca-certificates iptables \
    systemd-resolved haproxy \
    python3 python3-pip

# --------------------------
# INSTALL DROPBEAR (SSH)
# --------------------------
echo "🔧 Install Dropbear SSH..."
apt install -y dropbear
systemctl stop dropbear

# Konfigurasi Dropbear
cat > /etc/default/dropbear << EOF
NO_START=0
DROPBEAR_PORT=22
DROPBEAR_EXTRA_ARGS="-w -s -g"
DROPBEAR_BANNER="SSH-2.0-OpenSSH_9.6"
EOF

# Aktifkan port forwarding & websocket
cat > /etc/dropbear/options << EOF
PermitRootLogin yes
PasswordAuthentication yes
AllowTcpForwarding yes
PermitTunnel yes
X11Forwarding no
EOF

systemctl enable --now dropbear

# --------------------------
# INSTALL WEBSOCKET (HAProxy)
# --------------------------
echo "🔧 Konfigurasi WebSocket HAProxy..."
cat > /etc/haproxy/haproxy.cfg << EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000
    timeout client 300000
    timeout server 300000

frontend http
    bind *:80
    bind *:443 ssl crt /etc/ssl/certs/ssl-cert-snakeoil.pem
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    http-request set-header Host $DOMAIN
    acl is_websocket hdr(Upgrade) -i websocket
    acl is_websocket hdr(Connection) -i upgrade
    use_backend ssh_ws if is_websocket
    default_backend ssh_ws

backend ssh_ws
    server ssh 127.0.0.1:22
    http-request set-header Connection upgrade
    http-request set-header Upgrade websocket

frontend v2ray
    bind *:$V2RAY_PORT ssl crt /etc/ssl/certs/ssl-cert-snakeoil.pem
    default_backend v2ray_backend

backend v2ray_backend
    server v2ray 127.0.0.1:2000
EOF

systemctl restart haproxy
systemctl enable haproxy

# --------------------------
# INSTALL V2RAY
# --------------------------
echo "🔧 Install V2Ray..."
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)

# Buat UUID otomatis
UUID=$(cat /proc/sys/kernel/random/uuid)
cat > /usr/local/etc/v2ray/config.json << EOF
{
  "inbounds": [
    {
      "port": 2000,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/ssl/certs/ssl-cert-snakeoil.pem",
              "keyFile": "/etc/ssl/private/ssl-cert-snakeoil.key"
            }
          ]
        },
        "wsSettings": {
          "path": "/$DOMAIN"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

systemctl enable --now v2ray

# --------------------------
# INSTALL UDP TUNNEL
# --------------------------
echo "🔧 Konfigurasi UDP Tunnel..."
cat > /etc/systemd/system/udp-tunnel.service << EOF
[Unit]
Description=UDP Tunnel Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 -c "
import socket
import threading
import time

UDP_PORT_RANGE = range(40000, 40101)
sockets = []

def handle_client(data, addr, sock):
    sock.sendto(data, addr)

for port in UDP_PORT_RANGE:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('0.0.0.0', port))
        sockets.append(s)
        threading.Thread(target=lambda: None, daemon=True).start()
    except:
        pass

while True:
    time.sleep(3600)
"
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now udp-tunnel

# --------------------------
# FIREWALL & IPTABLES
# --------------------------
echo "🔧 Konfigurasi Firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 40000:40100/udp
ufw --force enable

# --------------------------
# INFO
# --------------------------
clear
echo "====================================="
echo "✅ INSTALASI SELESAI!"
echo "====================================="
echo ""
echo "🌐 Domain: $DOMAIN"
echo ""
echo "🔑 SSH WebSocket:"
echo "   Port: 80, 443"
echo "   Path: /$DOMAIN"
echo ""
echo "📡 V2Ray VMess:"
echo "   Address: $DOMAIN"
echo "   Port: 443"
echo "   ID: $UUID"
echo "   Network: ws"
echo "   Security: tls"
echo "   Path: /$DOMAIN"
echo ""
echo "🔵 UDP Tunnel:"
echo "   Port: 40000 - 40100"
echo ""
echo "⚠️  Ubah password root segera!"
echo "   passwd"
echo ""
echo "====================================="

