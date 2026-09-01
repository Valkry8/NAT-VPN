# 🚀 VPN All-in-One Ultimate — SSH WS + V2Ray + UDP + SlowDNS

**Domain:** `tunel.randi.biz.id`
**Support:** Ubuntu 22.04 / 24.04 LTS
**RAM Minimal:** 512MB | **CPU:** 1 Core

## ✅ Fitur Lengkap

| Layanan | Protokol | Port | Status |
|---|---|---|---|
| 🔑 SSH WebSocket | Dropbear + HAProxy | 80 / 443 | ✅ |
| 📡 V2Ray VMess | WebSocket + TLS | 443 | ✅ |
| 🔵 UDP Tunnel | Python UDP Relay | 40000–40100 | ✅ |
| 🟢 SlowDNS Server | DNS Tunnel | 53 / 5353 | ✅ |

## 📥 Cara Install di VPS

```bash
# Login sebagai root
sudo su

# Download & jalankan installer
wget -q https://raw.githubusercontent.com/[USERNAME]/[REPO]/main/install.sh -O install.sh
chmod +x install.sh
./install.sh
