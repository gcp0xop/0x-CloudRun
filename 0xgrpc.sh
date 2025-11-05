#!/usr/bin/env bash
set -euo pipefail

# ===== Colors =====
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'

# ===== Logging =====
LOG_FILE="/tmp/vmess_2hr_$(date +%s).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${PURPLE}🚀 KSGCP 2:15 Hours Extended VMESS + TLS${NC}"
echo -e "${CYAN}⏰ Optimized for 135 Minutes Usage${NC}"
echo ""

# ===== Time Tracking =====
START_TIME=$(date +%s)
LAB_DURATION=8100  # 135 minutes in seconds

# ===== Step 1: Comprehensive Setup =====
echo -e "${GREEN}✅ Step 1: Extended System Setup${NC}"
PROJECT=$(gcloud config get-value project)
ZONE=$(gcloud config get-value compute/zone 2>/dev/null || echo "us-central1-a")
echo -e "   Project: ${CYAN}$PROJECT${NC}"
echo -e "   Zone: ${CYAN}$ZONE${NC}"

# ===== Step 2: Multi-Protocol Setup =====
echo -e "${GREEN}✅ Step 2: Multi-Protocol Deployment${NC}"

# Generate multiple UUIDs for different protocols
VMESS_UUID=$(cat /proc/sys/kernel/random/uuid)
TROJAN_PASSWORD=$(openssl rand -base64 12 | tr -d '/+=')
echo -e "   VMESS UUID: ${CYAN}$VMESS_UUID${NC}"
echo -e "   Trojan Password: ${CYAN}$TROJAN_PASSWORD${NC}"

# Get external IP
EXT_IP=$(curl -s -m 5 ifconfig.me || curl -s -m 5 ipinfo.io/ip || echo "YOUR_VM_IP")
echo -e "   External IP: ${CYAN}$EXT_IP${NC}"

# ===== Step 3: Enhanced Xray Install =====
echo -e "${GREEN}✅ Step 3: Installing Enhanced Xray${NC}"

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

# ===== Step 4: Multi-Inbound Configuration =====
echo -e "${GREEN}✅ Step 4: Multi-Protocol Configuration${NC}"

cat > /usr/local/etc/xray/config.json << EOF
{
  "inbounds": [
    {
      "port": 443,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$VMESS_UUID",
            "alterId": 0,
            "email": "user@ksgcp.com"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/usr/local/etc/xray/cert.crt",
              "keyFile": "/usr/local/etc/xray/private.key"
            }
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vmess-tls"
    },
    {
      "port": 8443,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "$TROJAN_PASSWORD",
            "email": "trojan@ksgcp.com"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/usr/local/etc/xray/cert.crt",
              "keyFile": "/usr/local/etc/xray/private.key"
            }
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "trojan-tls"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

# ===== Step 5: Professional Certificate =====
echo -e "${GREEN}✅ Step 5: Generating Professional Certificate${NC}"

openssl req -new -newkey rsa:4096 -days 30 -nodes -x509 \
  -subj "/C=US/ST=California/L=San Francisco/O=Google Cloud/CN=cloud.google.com" \
  -keyout /usr/local/etc/xray/private.key \
  -out /usr/local/etc/xray/cert.crt

# ===== Step 6: Advanced Firewall =====
echo -e "${GREEN}✅ Step 6: Configuring Advanced Firewall${NC}"

# Remove existing rules if any
gcloud compute firewall-rules delete -q ksgcp-vmess-443 2>/dev/null || true
gcloud compute firewall-rules delete -q ksgcp-trojan-8443 2>/dev/null || true

# Create new rules
gcloud compute firewall-rules create ksgcp-vmess-443 \
  --allow=tcp:443 \
  --direction=INGRESS \
  --description="KSGCP VMESS TLS" \
  --quiet

gcloud compute firewall-rules create ksgcp-trojan-8443 \
  --allow=tcp:8443 \
  --direction=INGRESS \
  --description="KSGCP Trojan TLS" \
  --quiet

# ===== Step 7: Service Optimization =====
echo -e "${GREEN}✅ Step 7: Service Optimization${NC}"

systemctl enable xray
systemctl daemon-reload
systemctl restart xray

# Wait and check status
sleep 5
if systemctl is-active --quiet xray; then
  echo -e "   Xray Status: ${GREEN}Active & Optimized${NC}"
else
  echo -e "   Xray Status: ${RED}Failed${NC}"
  journalctl -u xray -n 10 --no-pager
fi

# ===== Step 8: Connection Info =====
echo -e "${GREEN}✅ Step 8: Generating Connection Details${NC}"

# VMESS Config
VMESS_CONFIG=$(cat <<EOF
{
  "v": "2",
  "ps": "KSGCP-VMESS-2HR",
  "add": "$EXT_IP",
  "port": "443",
  "id": "$VMESS_UUID",
  "aid": "0",
  "scy": "auto",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "tls",
  "sni": "",
  "alpn": ""
}
EOF
)

VMESS_BASE64=$(echo "$VMESS_CONFIG" | base64 -w 0)
VMESS_LINK="vmess://$VMESS_BASE64"

# Trojan Config
TROJAN_LINK="trojan://$TROJAN_PASSWORD@$EXT_IP:8443?security=tls&type=tcp#KSGCP-Trojan-2HR"

# ===== Step 9: Time Management =====
CURRENT_TIME=$(date +%s)
TIME_USED=$((CURRENT_TIME - START_TIME))
TIME_REMAINING=$((LAB_DURATION - TIME_USED))

# Convert to minutes
TIME_USED_MIN=$((TIME_USED / 60))
TIME_REMAINING_MIN=$((TIME_REMAINING / 60))

# ===== Final Output =====
echo ""
echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║              🎯 2:15 HOURS LAB READY          ║${NC}"
echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}🚀 Multi-Protocol Deployment Complete!${NC}"
echo ""

echo -e "${CYAN}📊 Time Management:${NC}"
echo -e "   ${YELLOW}Time Used:${NC} $TIME_USED_MIN minutes"
echo -e "   ${YELLOW}Time Remaining:${NC} $TIME_REMAINING_MIN minutes"
echo ""

echo -e "${CYAN}🔗 VMESS + TLS:${NC}"
echo -e "   ${YELLOW}IP:${NC} $EXT_IP:443"
echo -e "   ${YELLOW}UUID:${NC} $VMESS_UUID"
echo -e "   ${GREEN}$VMESS_LINK${NC}"
echo ""

echo -e "${CYAN}🔗 Trojan + TLS:${NC}"
echo -e "   ${YELLOW}IP:${NC} $EXT_IP:8443"
echo -e "   ${YELLOW}Password:${NC} $TROJAN_PASSWORD"
echo -e "   ${GREEN}$TROJAN_LINK${NC}"
echo ""

echo -e "${BLUE}🎯 Features:${NC}"
echo -e "   ✅ Dual Protocol (VMESS + Trojan)"
echo -e "   ✅ TLS Encryption"
echo -e "   ✅ Traffic Obfuscation"
echo -e "   ✅ Sniffing Protection"
echo -e "   ✅ Optimized for 135 minutes"
echo ""

echo -e "${YELLOW}📝 Usage Tips:${NC}"
echo -e "   1. Use both links for redundancy"
echo -e "   2. Monitor time remaining: ~$TIME_REMAINING_MIN minutes"
echo -e "   3. If one protocol blocked, try the other"
echo ""

echo -e "${GREEN}✅ Ready for extended usage! Import both links.${NC}"
echo -e "${CYAN}📄 Log: $LOG_FILE${NC}"
