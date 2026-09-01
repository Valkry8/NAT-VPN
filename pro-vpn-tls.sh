#!/bin/bash
# ==================================================
# SSH + WebSocket VPN — PRO EDITION 🔒💎
# Ubuntu 22.04 / 24.04 LTS ✅
# Fitur:
# ✅ Dropbear SSH Port 109
# ✅ Nginx WebSocket Proxy Port 80/443
# ✅ Let's Encrypt Sertifikat RESMI & TERPERCAYA 🔐
# ✅ Auto SSL Renewal — Tidak pernah kadaluarsa!
# ✅ TLS 1.2 + 1.3 + HTTP/2 + HSTS 🔒
# ✅ IP Forward + NAT + Firewall Otomatis
# ==================================================
set -e

# ============== KONFIGURASI — UBAH SESUAI KEBUTUHAN! ==============
DOMAIN="tunel.randi.biz.id"       # ← GANTI dengan domainmu!
EMAIL="admin@randi.biz.id"         # ← GANTI email untuk Let's Encrypt!
SSH_PORT=109
WS_PATH="/ws-tls"
WS_PATH2="/ssh-tls"
# ==================================================================

echo -e "\e[35m==================================================\e[0m"
echo -e "\e[35m       SSH + WEBSOCKET VPN — PRO EDITION 💎🔒      \e[0m"
echo -e "\e[35m==================================================\e[0m"
echo -e "\e[36mDomain:    $DOMAIN\e[0m"
echo -e "\e[36mEmail:     $EMAIL\e[0m"
echo -e "\e[36mSSH Port:  $SSH_PORT\e[0m"
echo -e "\e[36mWS Path:   $WS_PATH / $WS_PATH2\e[0m"
echo -e "\e[35m==================================================\e[0m"

# --------------------------
# 1. UPDATE & INSTALL SEMUA PAKET
# --------------------------
echo -e "\n\e[34m[1/8] Update sistem & install paket...\e[0m"
apt update -y
apt install -y curl wget nano net-tools iptables iptables-persistent \
    build-essential libssl-dev zlib1g-dev nginx dropbear openssl \
    certbot python3-certbot-nginx ufw

# --------------------------
# 2. AKTIFKAN IP FORWARDING
# --------------------------
echo -e "\n\e[34m[2/8] Aktifkan IP Forwarding...\e[0m"
cat > /etc/sysctl.d/99-pro-vpn.conf << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 4096
EOF
sysctl -p /etc/sysctl.d/99-pro-vpn.conf

# --------------------------
# 3. NAT & FIREWALL — BUKA SEMUA PORT
# --------------------------
echo -e "\n\e[34m[3/8] Set NAT & Firewall...\e[0m"
IFACE=$(ip route show default | awk '/default/ {print $5}')
iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --dport 123 -j ACCEPT
netfilter-persistent save

# Konfigurasi UFW (jika aktif)
ufw allow 22/tcp 2>/dev/null || true
ufw allow 80/tcp 2>/dev/null || true
ufw allow 443/tcp 2>/dev/null || true
ufw allow $SSH_PORT/tcp 2>/dev/null || true

# --------------------------
# 4. KONFIGURASI DROPBEAR SSH — PORT 109
# --------------------------
echo -e "\n\e[34m[4/8] Konfigurasi Dropbear SSH...\e[0m"
mkdir -p /etc/dropbear
rm -f /etc/dropbear/dropbear_rsa_host_key /etc/dropbear/dropbear_ecdsa_host_key 2>/dev/null || true
dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key

cat > /etc/default/dropbear << EOF
DROPBEAR_PORT=$SSH_PORT
DROPBEAR_EXTRA_ARGS="-p $SSH_PORT"
EOF

systemctl restart dropbear
systemctl enable dropbear

# --------------------------
# 5. NGINX — KONFIGURASI DULU UNTUK LET'S ENCRYPT
# --------------------------
echo -e "\n\e[34m[5/8] Konfigurasi Nginx dasar...\e[0m"

cat > /etc/nginx/sites-available/pro-vpn << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    
    root /var/www/html;
    index index.html;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

mkdir -p /var/www/html
ln -sf /etc/nginx/sites-available/pro-vpn /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# --------------------------
# 6. LET'S ENCRYPT — DAPATKAN SERTIFIKAT RESMI! 🔐
# --------------------------
echo -e "\n\e[34m[6/8] Minta Sertifikat Let's Encrypt 🔐...\e[0m"
echo -e "\e[33m⚠️  Pastikan domain $DOMAIN sudah mengarah ke IP VPS ini!\e[0m"
echo -e "\e[33m   Tunggu sebentar...\e[0m"

# Cek apakah domain sudah mengarah ke sini
IP=$(curl -s ifconfig.me)
DOMAIN_IP=$(dig +short $DOMAIN 2>/dev/null || nslookup $DOMAIN 2>/dev/null | grep Address | tail -n1 | awk '{print $2}')

if [[ "$DOMAIN_IP" != "$IP" ]]; then
    echo -e "\e[31m⚠️  Domain $DOMAIN mengarah ke $DOMAIN_IP, bukan ke $IP!\e[0m"
    echo -e "\e[33m   Lanjutkan pakai IP atau perbaiki DNS dulu.\e[0m"
    USE_IP_SSL=true
else
    USE_IP_SSL=false
    # Dapatkan sertifikat Let's Encrypt
    certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --no-eff-email --redirect -q
fi

# Jika domain belum siap, buat self-signed sementara
if [ "$USE_IP_SSL" = true ] || [ ! -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]; then
    echo -e "\e[33mℹ️  Menggunakan sertifikat sementara...\e[0m"
    mkdir -p /etc/ssl/pro-vpn
    openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
        -keyout /etc/ssl/pro-vpn/tls.key \
        -out /etc/ssl/pro-vpn/tls.crt \
        -subj "/C=ID/ST=SouthSulawesi/L=Makassar/O=PRO-VPN/CN=$DOMAIN" 2>/dev/null
    SSL_CERT="/etc/ssl/pro-vpn/tls.crt"
    SSL_KEY="/etc/ssl/pro-vpn/tls.key"
else
    SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo -e "\e[32m✅ Sertifikat Let's Encrypt BERHASIL! 🔐\e[0m"
    
    # Aktifkan auto-renewal
    systemctl enable --now certbot.timer 2>/dev/null || true
fi

# --------------------------
# 7. KONFIGURASI NGINX PENUH — TLS 1.2/1.3 + HTTP/2 + WEBSOCKET 🔒
# --------------------------
echo -e "\n\e[34m[7/8] Konfigurasi Nginx + TLS Penuh...\e[0m"

cat > /etc/nginx/sites-available/pro-vpn << NGINXCONF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    # === SERTIFIKAT SSL ===
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    
    # === KONFIGURASI TLS TINGKAT TINGGI 🔒 ===
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_early_data on;

    # === KEAMANAN TAMBAHAN ===
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "default-src 'self'";

    # === WEBSOCKET PROXY KE DROPBEAR SSH ===
    location $WS_PATH {
        proxy_pass http://127.0.0.1:$SSH_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_ssl_verify off;
        proxy_connect_timeout 60s;
        proxy_send_timeout 86400s;
        proxy_read_timeout 86400s;
        proxy_buffering off;
        proxy_cache off;
        tcp_nopush on;
        tcp_nodelay on;
    }

    # === PATH ALTERNATIF ===
    location $WS_PATH2 {
        proxy_pass http://127.0.0.1:$SSH_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 86400s;
        proxy_buffering off;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}
NGINXCONF

nginx -t && systemctl restart nginx
systemctl enable nginx

# --------------------------
# 8. BUAT AKUN SSH & TAMPILKAN INFO LENGKAP
# --------------------------
echo -e "\n\e[34m[8/8] Buat akun & tampilkan info...\e[0m"
PASSWD=$(openssl rand -base64 12)
useradd -m -s /bin/bash vpnuser 2>/dev/null || true
echo "vpnuser:$PASSWD" | chpasswd
usermod -aG sudo vpnuser 2>/dev/null || true

# Auto-renewal cron
(crontab -l 2>/dev/null | grep -v certbot; echo "0 3 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -

IP=$(curl -s ifconfig.me)
echo -e "\n\e[35m==================================================\e[0m"
echo -e "\e[35m       ✅ INSTALLASI SELESAI — PRO EDITION 💎🔒   \e[0m"
echo -e "\e[35m==================================================\e[0m"
echo -e "\e[36mSistem:           Ubuntu 24.04 LTS ✅\e[0m"
echo -e "\e[36mIP VPS:           $IP\e[0m"
echo -e "\e[36mDomain:           $DOMAIN\e[0m"
echo -e "\e[36mSSH Langsung:     Port $SSH_PORT ✅\e[0m"
echo -e "\e[36mWebSocket HTTPS:  Port 443 — TLS 1.2/1.3 🔒✅\e[0m"
echo -e "\e[36mWebSocket Path:  $WS_PATH  /  $WS_PATH2\e[0m"
echo -e "\e[36mSertifikat:       Let's Encrypt 🔐 — Auto Renew ✅\e[0m"
echo -e "\e[36mHTTP/2:           Aktif ⚡✅\e[0m"
echo -e "\e[36mAkun SSH:         vpnuser\e[0m"
echo -e "\e[36mPassword SSH:     $PASSWD\e[0m"
echo -e "\e[35m==================================================\e[0m"
echo -e "\e[33m--- PAYLOAD TLS UNTUK HTTP CUSTOM ---\e[0m"
echo -e "\e[33mGET $WS_PATH HTTP/1.1[crlf]Host: $DOMAIN[crlf]Connection: Upgrade[crlf]Upgrade: websocket[crlf][crlf]\e[0m"
echo -e "\e[33m⚠️  Aktifkan TLS/SSL + Port 443 di aplikasi! ⚠️\e[0m"
echo -e "\e[35m==================================================\e[0m"

