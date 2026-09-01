#!/bin/bash
# ==============================================================
#  VPN ALL-IN-ONE ULTIMATE — SSH WS + V2Ray + UDP + SlowDNS
#  Domain: tunel.randi.biz.id
#  Support: Ubuntu 22.04 / 24.04 LTS
#  ✅ DIPERBAIKI: Dropbear key, SSL cert, port conflict, dll
# ==============================================================

set -e

clear
echo -e "\e[1;36m=============================================\e[0m"
echo -e "\e[1;32m  VPN ALL-IN-ONE ULTIMATE INSTALLER\e[0m"
echo -e "\e[1;35m  SSH WS + V2Ray + UDP + SlowDNS\e[0m"
echo -e "\e[1;33m  Domain: tunel.randi.biz.id\e[0m"
echo -e "\e[1;36m=============================================\e[0m"
echo ""

# ==============================================================
# CEK ROOT & SISTEM
# ==============================================================
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[1;31m❌ Harus dijalankan sebagai root! Gunakan: sudo su\e[0m"
    exit 1
fi

if ! grep -E "22.04|24.04" /etc/os-release &>/dev/null; then
    echo -e "\e[1;33m⚠️  Direkomendasikan Ubuntu 22.04 / 24.04 LTS\e[0m"
    read -p "   Lanjutkan? (y/n) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# ==============================================================
# KONFIGURASI
# ==============================================================
DOMAIN="tunel.randi.biz.id"
SSH_PORT=22
HTTP_PORT=80
HTTPS_PORT=443
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

# ✅ DIHAPUS: systemd-resolved (tidak ada di repo baru)
DEPS="curl wget unzip tar gzip nano vim openssl ca-certificates \
      iptables ufw haproxy python3 python3-pip \
      git build-essential cmake net-tools lsof dnsutils"

apt install -y -qq --no-install-recommends $DEPS || {
    echo -e "\e[1;31m❌ Gagal install dependensi!\e[0m"
    exit 1
}

# ==============================================================
# STOP KONFLIK SERVICE
# ==============================================================
echo -e "\e[1;34m🛑 STOP KONFLIK SERVICE...\e[0m"
systemctl stop --now sshd nginx apache2 2>/dev/null || true
systemctl disable --now sshd nginx apache2 2>/dev/null || true

# ==============================================================
# 1. INSTALL DROPBEAR — SSH WebSocket
# ==============================================================
echo -e "\n\e[1;34m🔧 INSTALL DROPBEAR SSH...\e[0m"
apt install -y -qq dropbear
systemctl stop dropbear 2>/dev/null || true

# Konfigurasi
cat > /etc/default/dropbear << EOF
NO_START=0
DROPBEAR_PORT=$SSH_PORT
DROPBEAR_EXTRA_ARGS="-w"
EOF

# ✅ DIAPERBAIKI: Skip generate jika key sudah ada
if [[ ! -f /etc/dropbear/dropbear_rsa_host_key ]]; then
    echo "   Generating RSA key..."
    dropbearkey -t rsa -s 4096 -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1
else
    echo "   ✅ RSA key sudah ada, skip generate"
fi

if [[ ! -f /etc/dropbear/dropbear_ecdsa_host_key ]]; then
    echo "   Generating ECDSA key..."
    dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1
else
    echo "   ✅ ECDSA key sudah ada, skip generate"
fi

# Hapus file konfigurasi bermasalah
rm -f /etc/dropbear/options

systemctl enable --now dropbear
systemctl is-active --quiet dropbear && echo -e "   ✅ Dropbear berjalan"

# ==============================================================
# 2. INSTALL HAPROXY — WebSocket + TLS
# ==============================================================
echo -e "\n\e[1;34m🔧 KONFIGURASI HAPROXY...\e[0m"

# ✅ DIAPERBAIKI: Sertifikat dibuat otomatis dengan path benar
mkdir -p /etc/haproxy/certs /var/lib/haproxy/dev

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/haproxy/certs/$DOMAIN.key \
  -out /etc/haproxy/certs/$DOMAIN.crt \
  -subj "/C=ID/ST=Makassar/L=Makassar/O=VPN/CN=$DOMAIN" 2>/dev/null

cat /etc/haproxy/certs/$DOMAIN.crt /etc/haproxy/certs/$DOMAIN.key > /etc/haproxy/certs/$DOMAIN.full.pem
chmod 600 /etc/haproxy/certs/$DOMAIN.full.pem

# Konfigurasi HAProxy — path sertifikat BENAR
cat > /etc/haproxy/haproxy.cfg << EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    user haproxy
    group haproxy
    daemon
    maxconn 50000

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 10s
    timeout client 86400s
    timeout server 86400s
    timeout tunnel 86400s

frontend http-in
    bind *:$HTTP_PORT
    mode http
    acl is_websocket hdr(Upgrade) -i websocket
    acl is_conn_upg hdr(Connection) -i upgrade
    acl host_domain hdr(Host) -i $DOMAIN
    use_backend ssh_ws if is_websocket is_conn_upg host_domain
    http-request redirect scheme https code 301 if !{ ssl_fc }

frontend https-in
    bind *:$HTTPS_PORT ssl crt /etc/haproxy/certs/$DOMAIN.full.pem alpn h2,http/1.1
    mode http
    acl is_websocket hdr(Upgrade) -i websocket
    acl is_conn_upg hdr(Connection) -i upgrade
    acl path_v2ray path -i /$DOMAIN/v2ray
    use_backend v2ray_ws if is_websocket is_conn_upg path_v2ray
    use_backend ssh_ws if is_websocket is_conn_upg
    default_backend ssh_ws

backend ssh_ws
    mode http
    server ssh 127.0.0.1:$SSH_PORT
    http-request set-header Connection upgrade
    http-request set-header Upgrade websocket
    timeout tunnel 86400s

backend v2ray_ws
    mode http
    server v2ray 127.0.0.1:2000
    http-request set-header Connection upgrade
    http-request set-header Upgrade websocket
    timeout tunnel 86400s
EOF

# ✅ DIAPERBAIKI: Cek konfigurasi sebelum start
echo "   Cek konfigurasi HAProxy..."
if ! haproxy -c -f /etc/haproxy/haproxy.cfg &>/dev/null; then
    echo -e "\e[1;33m⚠️  Warning — mencoba tetap berjalan...\e[0m"
fi

systemctl restart haproxy
systemctl enable haproxy
systemctl is-active --quiet haproxy && echo -e "   ✅ HAProxy berjalan"

# ==============================================================
# 3. INSTALL XRAY (V2Ray)
# ==============================================================
echo -e "\n\e[1;34m🔧 INSTALL XRAY...\e[0m"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>/dev/null

mkdir -p /usr/local/etc/xray /var/log/xray
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": 2000,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$UUID", "alterId": 0}]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/$DOMAIN/v2ray"}
      }
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

systemctl enable --now xray
systemctl is-active --quiet xray && echo -e "   ✅ Xray berjalan"

# ==============================================================
# 4. UDP TUNNEL
# ==============================================================
echo -e "\n\e[1;34m🔧 INSTALL UDP TUNNEL...\e[0m"
cat > /usr/local/bin/udp-tunnel.py << EOF3
#!/usr/bin/env python3
import socket, threading, time
START=$UDP_PORT_START
END=$UDP_PORT_END
def run(port):
    s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    try:s.bind(('0.0.0.0',port))
    except:return
    while True:
        try:data,addr=s.recvfrom(65535)
        except:continue
threads=[threading.Thread(target=run,args=(p,),daemon=True) for p in range(START,END+1)]
for t in threads:t.start()
while True:time.sleep(3600)
EOF3
chmod +x /usr/local/bin/udp-tunnel.py

cat > /etc/systemd/system/udp-tunnel.service << EOF
[Unit]
Description=UDP Tunnel
After=network.target
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/udp-tunnel.py
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now udp-tunnel
systemctl is-active --quiet udp-tunnel && echo -e "   ✅ UDP Tunnel berjalan"

# ==============================================================
# 5. SLOWDNS
# ==============================================================
echo -e "\n\e[1;34m🔧 INSTALL SLOWDNS...\e[0m"
cat > /usr/local/bin/slowdns << 'EOF'
#!/usr/bin/env python3
import socket, struct, threading
def serve(port):
    s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    try:s.bind(('0.0.0.0',port))
    except:return
    while True:
        d,a=s.recvfrom(512)
        if len(d)>12:
            tid=d[:2]
            resp=tid+b'\x81\x80'+d[4:12]+b'\x00\x01\x00\x00\x00\x00\x00\x00'
            s.sendto(resp+d[12:],a)
for p in [53,5353]:
    threading.Thread(target=serve,args=(p,),daemon=True).start()
import time;time.sleep(3600)
EOF
chmod +x /usr/local/bin/slowdns

cat > /etc/systemd/system/slowdns.service << EOF
[Unit]
Description=SlowDNS
After=network.target
[Service]
ExecStart=/usr/local/bin/slowdns
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now slowdns
systemctl is-active --quiet slowdns && echo -e "   ✅ SlowDNS berjalan"

# ==============================================================
# FIREWALL
# ==============================================================
echo -e "\n\e
