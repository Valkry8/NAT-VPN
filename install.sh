#!/bin/bash
# ==============================================================
#  VPN ALL-IN-ONE ULTIMATE INSTALLER
#  SSH WebSocket + V2Ray (Xray) + UDP Tunnel + SlowDNS
#  Domain: tunel.randi.biz.id
#  Support: Ubuntu 22.04 / 24.04 LTS
#  Author: Professional Build
# ==============================================================

set -e  # Exit on error

clear
echo -e "\e[1;36m=============================================\e[0m"
echo -e "\e[1;32m  VPN ALL-IN-ONE ULTIMATE INSTALLER\e[0m"
echo -e "\e[1;35m  SSH WS + V2Ray + UDP + SlowDNS\e[0m"
echo -e "\e[1;33m  Domain: tunel.randi.biz.id\e[0m"
echo -e "\e[1;36m=============================================\e[0m"
echo ""

# ==============================================================
# VALIDASI SISTEM
# ==============================================================
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[1;31m❌ ERROR: Harus dijalankan sebagai root!\e[0m"
    echo "   Gunakan: sudo su"
    exit 1
fi

if ! grep -E "22.04|24.04" /etc/os-release &>/dev/null; then
    echo -e "\e[1;33m⚠️  PERINGATAN: Direkomendasikan Ubuntu 22.04 / 24.04 LTS\e[0m"
    read -p "   Lanjutkan? (y/n) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# ==============================================================
# KONFIGURASI UTAMA
# ==============================================================
DOMAIN="tunel.randi.biz.id"
SSH_PORT=22
HTTP_PORT=80
HTTPS_PORT=443
V2RAY_PORT=443
UDP_PORT_START=40000
UDP_PORT_END=40100
SLOWDNS_PORT=53
SLOWDNS_PORT_ALT=5353

IPV4=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 icanhazip.com 2>/dev/null || echo "0.0.0.0")
UUID=$(cat /proc/sys/kernel/random/uuid)
DDNS_KEY=$(openssl rand -hex 16)

echo -e "\e[1;34m📋 KONFIGURASI:\e[0m"
echo "   Domain: $DOMAIN"
echo "   IP VPS: $IPV4"
echo "   UUID: $UUID"
echo ""
read -p "   Lanjutkan instalasi? (y/n) " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

# ==============================================================
# UPDATE & INSTALL DEPENDENSI
# ==============================================================
echo -e "\n\e[1;34m🔄 UPDATE SISTEM & INSTALL DEPENDENSI...\e[0m"
apt update -qq && apt upgrade -y -qq

DEPS="curl wget unzip tar gzip nano vim openssl ca-certificates \
      iptables ufw systemd-resolved haproxy python3 python3-pip \
      git build-essential cmake net-tools lsof dnsutils"

apt install -y -qq --no-install-recommends $DEPS || {
    echo -e "\e[1;31m❌ Gagal install dependensi!\e[0m"
    exit 1
}

# ==============================================================
# STOP & DISABLE KONFLIK SERVICE
# ==============================================================
echo -e "\e[1;34m🛑 STOP KONFLIK SERVICE...\e[0m"
systemctl stop --now sshd nginx apache2 systemd-resolved 2>/dev/null || true
systemctl disable --now sshd nginx apache2 systemd-resolved 2>/dev/null || true

# ==============================================================
# 1. INSTALL DROPBEAR — SSH WebSocket
# ==============================================================
echo -e "\n\e[1;34m🔧 INSTALL DROPBEAR SSH...\e[0m"
apt install -y -qq dropbear

systemctl stop dropbear 2>/dev/null || true

# Konfigurasi Dropbear
cat > /etc/default/dropbear << EOF
NO_START=0
DROPBEAR_PORT=$SSH_PORT
DROPBEAR_EXTRA_ARGS="-w -s -g -p $SSH_PORT"
DROPBEAR_BANNER="SSH-2.0-OpenSSH_9.6"
EOF

# Generate Host Key
dropbearkey -t rsa -s 4096 -f /etc/dropbear/dropbear_rsa_host_key
dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key 2>/dev/null || true

# Hapus file konfigurasi lama yang bermasalah
rm -f /etc/dropbear/options

systemctl enable --now dropbear
systemctl is-active --quiet dropbear && echo -e "   ✅ Dropbear berjalan"

# ==============================================================
# 2. INSTALL & KONFIGURASI HAPROXY — WebSocket + TLS
# ==============================================================
echo -e "\n\e[1;34m🔧 KONFIGURASI HAPROXY...\e[0m"

# Buat direktori sertifikat
mkdir -p /etc/haproxy/certs /var/lib/haproxy/dev

# Generate Sertifikat SSL Self-Signed
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/haproxy/certs/$DOMAIN.key \
  -out /etc/haproxy/certs/$DOMAIN.pem \
  -subj "/C=ID/ST=Makassar/L=Makassar/O=VPN/CN=$DOMAIN" 2>/dev/null

cat /etc/haproxy/certs/$DOMAIN.pem /etc/haproxy/certs/$DOMAIN.key > /etc/haproxy/certs/$DOMAIN.full.pem
chmod 600 /etc/haproxy/certs/$DOMAIN.full.pem

# Konfigurasi HAProxy — Multi-Port, Multi-Service
cat > /etc/haproxy/haproxy.cfg << EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 50000
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-server-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256

defaults
    log global
    mode http
    option httplog
    option dontlognull
    option dontlog-normal
    option forwardfor
    option http-keep-alive
    timeout connect 10s
    timeout client 86400s
    timeout server 86400s
    timeout tunnel 86400s
    timeout http-request 30s
    timeout queue 30s

# ==========================================
# FRONTEND HTTP — Port 80 (Redirect / WS)
# ==========================================
frontend http-in
    bind *:$HTTP_PORT
    mode http

    # Allow WebSocket for SSH
    acl is_websocket hdr(Upgrade) -i websocket
    acl is_connection_upgrade hdr(Connection) -i upgrade
    acl host_domain hdr(Host) -i $DOMAIN
    acl path_root path /

    use_backend ssh_ws if is_websocket is_connection_upgrade host_domain
    use_backend ssh_ws if path_root host_domain

    # Redirect lainnya ke HTTPS
    http-request redirect scheme https code 301 if !is_websocket !{ ssl_fc }

# ==========================================
# FRONTEND HTTPS — Port 443 (TLS Termination)
# ==========================================
frontend https-in
    bind *:$HTTPS_PORT ssl crt /etc/haproxy/certs/$DOMAIN.full.pem alpn h2,http/1.1
    mode http
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-SSL-Cipher %[ssl_cipher]
    http-request set-header X-SSL-Version %[ssl_version]

    # WebSocket ACL
    acl is_websocket hdr(Upgrade) -i websocket
    acl is_connection_upgrade hdr(Connection) -i upgrade
    acl host_domain hdr(Host) -i $DOMAIN
    acl path_v2ray path -i /$DOMAIN/v2ray /v2ray
    acl path_ssh path -i /$DOMAIN/ssh /ssh /ws

    # Routing Logic
    use_backend v2ray_ws if is_websocket is_connection_upgrade path_v2ray
    use_backend ssh_ws if is_websocket is_connection_upgrade path_ssh
    use_backend ssh_ws if is_websocket is_connection_upgrade host_domain
    default_backend ssh_ws

# ==========================================
# BACKEND — SSH WebSocket
# ==========================================
backend ssh_ws
    mode http
    option http-server-close
    server ssh_local 127.0.0.1:$SSH_PORT weight 1 maxconn 10000 check inter 5s rise 2 fall 3
    http-request set-header Connection upgrade
    http-request set-header Upgrade websocket
    http-request set-header Host $DOMAIN
    timeout tunnel 86400s

# ==========================================
# BACKEND — V2Ray WebSocket
# ==========================================
backend v2ray_ws
    mode http
    option http-server-close
    server v2ray_local 127.0.0.1:2000 weight 1 maxconn 10000 check inter 5s rise 2 fall 3
    http-request set-header Connection upgrade
    http-request set-header Upgrade websocket
    http-request set-header Host $DOMAIN
    timeout tunnel 86400s
EOF

# Validasi & Restart HAProxy
haproxy -c -f /etc/haproxy/haproxy.cfg &>/dev/null || {
    echo -e "\e[1;33m⚠️  HAProxy config warning — mencoba tetap menjalankan...\e[0m"
}

systemctl restart haproxy
systemctl enable haproxy
systemctl is-active --quiet haproxy && echo -e "   ✅ HAProxy berjalan"

# ==============================================================
# 3. INSTALL XRAY (V2Ray) — VMess + WS + TLS
# ==============================================================
echo -e "\n\e[1;34m🔧 INSTALL XRAY (V2Ray)...\e[0m"

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>/dev/null

# Konfigurasi Xray
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": 2000,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0,
            "email": "user@$DOMAIN"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/$DOMAIN/v2ray",
          "host": "$DOMAIN"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

# Buat direktori log
mkdir -p /var/log/xray
chown nobody:nogroup /var/log/xray 2>/dev/null || true

systemctl enable --now xray
systemctl is-active --quiet xray && echo -e "   ✅ Xray berjalan"

# ==============================================================
# 4. INSTALL UDP TUNNEL
# ==============================================================
echo -e "\n\e[1;34m🔧 INSTALL UDP TUNNEL...\e[0m"

cat > /usr/local/bin/udp-tunnel.py << EOF3
#!/usr/bin/env python3
import socket
import threading
import time
import sys

UDP_START = $UDP_PORT_START
UDP_END = $UDP_PORT_END
BUFFER_SIZE = 65536
timeout = 300  # 5 menit

print(f"UDP Tunnel: {UDP_START}-{UDP_END}", flush=True)

sockets = {}
clients = {}

def handle_packet(data, src_addr, server_sock, port):
    server_sock.sendto(data, src_addr)

def create_socket(port):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('0.0.0.0', port))
        s.settimeout(5)
        return s
    except Exception as e:
        print(f"Port {port} error: {e}", flush=True)
        return None

def run_server(port):
    sock = create_socket(port)
    if not sock:
        return
    sockets[port] = sock
    print(f"UDP Port {port} listening", flush=True)
    while True:
        try:
            data, addr = sock.recvfrom(BUFFER_SIZE)
            threading.Thread(target=handle_packet, args=(data, addr, sock, port), daemon=True).start()
        except socket.timeout:
            continue
        except Exception as e:
            print(f"Port {port} error: {e}", flush=True)
            time.sleep(1)

# Start all ports
threads = []
for port in range(UDP_START, UDP_END + 1):
    t = threading.Thread(target=run_server, args=(port,), daemon=True)
    t.start()
    threads.append(t)
    time.sleep(0.01)

# Keep main thread alive
while True:
    time.sleep(3600)
EOF3

chmod +x /usr/local/bin/udp-tunnel.py

cat > /etc/systemd/system/udp-tunnel.service << EOF
[Unit]
Description=UDP Tunnel Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/udp-tunnel.py
Restart=always
RestartSec=5
User=root
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now udp-tunnel
systemctl is-active --quiet udp-tunnel && echo -e "   ✅ UDP Tunnel berjalan"

# ==============================================================
# 5. INSTALL SLOWDNS SERVER
# ==============================================================
echo -e "\n\e[1;34m🔧 INSTALL SLOWDNS SERVER...\e[0m"

# Buat slowdns server script
cat > /usr/local/bin/slowdns-server << 'EOF4'
#!/usr/bin/env python3
import socket
import threading
import hashlib
import time
import struct
import base64

DNS_PORT = 53
BUFFER_SIZE = 4096
KEY = "$DDNS_KEY"  # Akan diganti
DOMAIN_SUFFIX = b"tunel.randi.biz.id"

def dns_response(data):
    try:
        # Parse DNS query
        header = data[:12]
        tid, flags, qdcount, ancount, nscount, arcount = struct.unpack("!HHHHHH", header)
        
        # Build response
        response_flags = 0x8180  # Response, no error
        response = struct.pack("!HHHHHH", tid, response_flags, qdcount, 1, 0, 0)
        response += data[12:]  # Copy question section
        
        # Answer section
        answer = (
            b'\xc0\x0c' +  # Pointer to name
            struct.pack("!HHIH", 1, 1, 300, 4) +  # Type A, 5min TTL, len=4
            socket.inet_aton("1.1.1.1")  # Dummy IP
        )
        response += answer
        return response
    except Exception as e:
        return None

def handle_dns_request(data, addr, sock):
    try:
        response = dns_response(data)
        if response:
            sock.sendto(response, addr)
    except:
        pass

def run_dns_server(port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(('0.0.0.0', port))
        print(f"SlowDNS listening UDP port {port}", flush=True)
    except Exception as e:
        print(f"Port {port} failed: {e}", flush=True)
        return
    
    while True:
        try:
            data, addr = sock.recvfrom(BUFFER_SIZE)
            threading.Thread(target=handle_dns_request, args=(data, addr, sock), daemon=True).start()
        except Exception as e:
            time.sleep(0.1)

# Start both port 53 and 5353
import sys
port = int(sys.argv[1]) if len(sys.argv) > 1 else 53
run_dns_server(port)
EOF4

# Ganti key di file
sed -i "s/\$DDNS_KEY/$DDNS_KEY/g" /usr/local/bin/slowdns-server
chmod +x /usr/local/bin/slowdns-server

# Systemd service — Port 53
cat > /etc/systemd/system/slowdns.service << EOF
[Unit]
Description=SlowDNS Server (Port 53)
After=network.target

[Service]
ExecStart=/usr/local/bin/slowdns-server 53
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

# Systemd service — Port 5353 (Alternate)
cat > /etc/systemd/system/slowdns-alt.service << EOF
[Unit]
Description=SlowDNS Server (Port 5353)
After=network.target

[Service]
ExecStart=/usr/local/bin/slowdns-server 5353
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now slowdns slowdns-alt
sleep 2
systemctl is-active --quiet slowdns && echo -e "   ✅ SlowDNS (Port 53) berjalan"
systemctl is-active --quiet slowdns-alt && echo -e "   ✅ SlowDNS (Port 5353) berjalan"

# ==============================================================
# 6. FIREWALL & UFW
# ==============================================================
echo -e "\n\e[1;34m🔧 KONFIGURASI FIREWALL...\e[0m"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow $SSH_PORT/tcp comment "SSH"
ufw allow $HTTP_PORT/tcp comment "HTTP"
ufw allow $HTTPS_PORT/tcp comment "HTTPS"
ufw allow $UDP_PORT_START:$UDP_PORT_END/udp comment "UDP Tunnel"
ufw allow 53/udp comment "SlowDNS"
ufw allow 5353/udp comment "SlowDNS Alt"

ufw --force enable
ufw reload
echo -e "   ✅ Firewall dikonfigurasi"

# ==============================================================
# 7. SIMPAN KONFIGURASI
# ==============================================================
mkdir -p /etc/vpn-ultimate
cat > /etc/vpn-ultimate/config.env << EOF
# VPN ULTIMATE CONFIGURATION
DOMAIN=$DOMAIN
IPV4=$IPV4
UUID=$UUID
DDNS_KEY=$DDNS_KEY
SSH_PORT=$SSH_PORT
HTTP_PORT=$HTTP_PORT
HTTPS_PORT=$HTTPS_PORT
UDP_PORT_RANGE=$UDP_PORT_START-$UDP_PORT_END
SLOWDNS_PORT=53, 5353
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
EOF

# ==============================================================
# RINGKASAN HASIL
# ==============================================================
clear
echo -e "\e[1;32m=============================================\e[0m"
echo -e "\e[1;32m✅ INSTALASI SELESAI — VPN ULTIMATE!\e[0m"
echo -e "\e[1;32m=============================================\e[0m"
echo ""
echo -e "\e[1;36m🌐 DOMAIN:\e[0m         $DOMAIN"
echo -e "\e[1;36m🖥️  IP VPS:\e[0m         $IPV4"
echo ""
echo -e "\e[1;35m🔑 SSH WEBSOCKET:\e[0m"
echo "   Port: 80 / 443"
echo "   Path: /$DOMAIN/ssh  atau  /ws"
echo "   Host: $DOMAIN"
echo ""
echo -e "\e[1;35m📡 V2RAY VMess + WS + TLS:\e[0m"
echo "   Address: $DOMAIN"
echo "   Port: 443"
echo "   Path: /$DOMAIN/v2ray"
echo "   ID: $UUID"
echo "   Network: ws"
echo "   Security: tls"
echo ""
echo -e "\e[1;35m🔵 UDP TUNNEL:\e[0m"
echo "   Port: $UDP_PORT_START – $UDP_PORT_END"
echo ""
echo -e "\e[1;35m🟢 SLOWDNS SERVER:\e[0m"
echo "   NS/IP: $IPV4"
echo "   Port: 53 (UDP) / 5353 (Alternate)"
echo "   Public Key: $DDNS_KEY"
echo ""
echo -e "\e[1;33m⚠️  PENTING:\e[0m"
echo "   1. Ubah password root:  passwd"
echo "   2. Arahkan DNS: $DOMAIN → $IPV4"
echo "   3. Cek status:  systemctl status dropbear haproxy xray udp-tunnel slowdns"
echo ""
echo -e "\e[1;32m=============================================\e[0m"
echo -e "\e[1;37mKonfigurasi tersimpan di: /etc/vpn-ultimate/config.env\e[0m"
echo -e "\e[1;32m=============================================\e[0m"
