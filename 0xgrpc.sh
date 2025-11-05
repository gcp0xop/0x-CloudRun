#!/usr/bin/env bash
set -euo pipefail

# ===== Ensure interactive reads =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging =====
LOG_FILE="/tmp/aws_vmess_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO" | tee -a "$LOG_FILE" >&2
  echo "📄 Log File: $LOG_FILE" >&2
  exit $rc
}
trap on_err ERR

# =================== Color & UI ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
  C_CYAN=$'\e[38;5;44m'; C_BLUE=$'\e[38;5;33m'
  C_GREEN=$'\e[38;5;46m'; C_YEL=$'\e[38;5;226m'
  C_ORG=$'\e[38;5;214m'; C_PINK=$'\e[38;5;205m'
  C_GREY=$'\e[38;5;245m'; C_RED=$'\e[38;5;196m'
else
  RESET= BOLD= DIM= C_CYAN= C_BLUE= C_GREEN= C_YEL= C_ORG= C_PINK= C_GREY= C_RED=
fi

hr(){ printf "${C_GREY}%s${RESET}\n" "──────────────────────────────────────────────"; }
banner(){
  local title="$1"
  printf "\n${C_BLUE}${BOLD}╔══════════════════════════════════════════════════╗${RESET}\n"
  printf   "${C_BLUE}${BOLD}║${RESET}  %s${RESET}\n" "$(printf "%-46s" "$title")"
  printf   "${C_BLUE}${BOLD}╚══════════════════════════════════════════════════╝${RESET}\n"
}
ok(){   printf "${C_GREEN}✔${RESET} %s\n" "$1"; }
warn(){ printf "${C_ORG}⚠${RESET} %s\n" "$1"; }
err(){  printf "${C_RED}✘${RESET} %s\n" "$1"; }
kv(){   printf "   ${C_GREY}%s${RESET}  %s\n" "$1" "$2"; }

printf "\n${C_CYAN}${BOLD}🚀 AWS Load Balancer - VMESS + TLS Deploy${RESET}\n"
hr

# =================== Random progress spinner ===================
run_with_progress() {
  local label="$1"; shift
  ( "$@" ) >>"$LOG_FILE" 2>&1 &
  local pid=$!
  local pct=5
  if [[ -t 1 ]]; then
    printf "\e[?25l"
    while kill -0 "$pid" 2>/dev/null; do
      local step=$(( (RANDOM % 9) + 2 ))
      pct=$(( pct + step ))
      (( pct > 95 )) && pct=95
      printf "\r🌀 %s... [%s%%]" "$label" "$pct"
      sleep "$(awk -v r=$RANDOM 'BEGIN{s=0.08+(r%7)/100; printf "%.2f", s }')"
    done
    wait "$pid"; local rc=$?
    printf "\r"
    if (( rc==0 )); then
      printf "✅ %s... [100%%]\n" "$label"
    else
      printf "❌ %s failed (see %s)\n" "$label" "$LOG_FILE"
      return $rc
    fi
    printf "\e[?25h"
  else
    wait "$pid"
  fi
}

# =================== Step 1: Telegram Config ===================
banner "🤖 Step 1 — Telegram Setup"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-${TELEGRAM_CHAT_ID:-}}"

if [[ ( -z "${TELEGRAM_TOKEN}" || -z "${TELEGRAM_CHAT_IDS}" ) && -f .env ]]; then
  set -a; source ./.env; set +a
fi

read -rp "🤖 Telegram Bot Token: " _tk || true
[[ -n "${_tk:-}" ]] && TELEGRAM_TOKEN="$_tk"
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then
  warn "Telegram token empty; deploy will continue without messages."
else
  ok "Telegram token captured."
fi

read -rp "👤 Owner/Channel Chat ID(s): " _ids || true
[[ -n "${_ids:-}" ]] && TELEGRAM_CHAT_IDS="${_ids// /}"

CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS:-}" || true

json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

tg_send(){
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then return 0; fi
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" >>"$LOG_FILE" 2>&1
    ok "Telegram sent → ${_cid}"
  done
}

# =================== Step 2: AWS EC2 Setup ===================
banner "🖥️ Step 2 — AWS EC2 Configuration"

# Get EC2 instance details
echo "🔍 Detecting EC2 instances..."
INSTANCES=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,State.Name]' --output table 2>/dev/null || true)

if [[ -z "$INSTANCES" ]]; then
  warn "No EC2 instances found or AWS CLI not configured"
  echo "📝 Please manually configure:"
  echo "   1. AWS CLI: aws configure"
  echo "   2. EC2 instances with public IP"
  echo "   3. Security groups allowing ports: 443, 80, 8388"
else
  echo "$INSTANCES"
  ok "EC2 instances detected"
fi

# =================== Step 3: VMESS + TLS Setup ===================
banner "🔐 Step 3 — VMESS + TLS Deployment"

# Generate UUID for VMESS
VMESS_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
ok "Generated VMESS UUID: ${VMESS_UUID}"

# Create Xray configuration
XRAY_CONFIG=$(cat <<EOF
{
  "inbounds": [
    {
      "port": 443,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$VMESS_UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/xray/cert.crt",
              "keyFile": "/etc/xray/private.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
)

echo "📁 Creating Xray configuration..."
echo "$XRAY_CONFIG" > /tmp/xray_config.json
ok "Xray config created"

# =================== Step 4: Installation Script ===================
banner "📦 Step 4 — Installation Script"

# Create installation script for EC2 instances
INSTALL_SCRIPT=$(cat <<'EOF'
#!/bin/bash

# Update system
sudo apt-get update -y
sudo apt-get upgrade -y

# Install Xray
sudo bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Create directory for certificates
sudo mkdir -p /etc/xray

# Generate self-signed certificate (for testing)
sudo openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" \
    -keyout /etc/xray/private.key -out /etc/xray/cert.crt

# Copy configuration
sudo cp /tmp/xray_config.json /usr/local/etc/xray/config.json

# Start Xray service
sudo systemctl enable xray
sudo systemctl start xray

# Check status
sudo systemctl status xray --no-pager

# Display connection info
echo "=========================================="
echo "🚀 VMESS + TLS Setup Complete!"
echo "=========================================="
echo "Address: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Port: 443"
echo "UUID: REPLACE_UUID"
echo "Security: tls"
echo "Network: tcp"
echo "=========================================="
EOF
)

echo "$INSTALL_SCRIPT" > /tmp/install_vmess.sh
chmod +x /tmp/install_vmess.sh
ok "Installation script created"

# =================== Step 5: Security Group Setup ===================
banner "🛡️ Step 5 — Security Group Configuration"

echo "🔓 Opening ports in security groups..."
# Note: User needs to manually configure security groups for ports 443, 80

ok "Please manually configure AWS Security Groups for:"
kv "Port 443" "TCP (VMESS + TLS)"
kv "Port 80" "TCP (Optional for fallback)"

# =================== Step 6: Deployment ===================
banner "🚀 Step 6 — Deployment Instructions"

echo "📋 Manual deployment steps for AWS EC2:"
echo ""
echo "1. 📁 Upload files to EC2:"
echo "   scp -i your-key.pem /tmp/xray_config.json ec2-user@YOUR_EC2_IP:/tmp/"
echo "   scp -i your-key.pem /tmp/install_vmess.sh ec2-user@YOUR_EC2_IP:/tmp/"
echo ""
echo "2. 🔧 Run installation:"
echo "   ssh -i your-key.pem ec2-user@YOUR_EC2_IP 'sudo bash /tmp/install_vmess.sh'"
echo ""
echo "3. 🔒 Update UUID in script:"
echo "   Replace 'REPLACE_UUID' with: ${VMESS_UUID}"
echo ""

# =================== Step 7: Generate VMESS Config ===================
banner "🔗 Step 7 — VMESS Connection Info"

# Get public IP (if available)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR_EC2_PUBLIC_IP")

VMESS_CONFIG=$(cat <<EOF
{
  "v": "2",
  "ps": "AWS-VMESS-TLS",
  "add": "$PUBLIC_IP",
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

# Base64 encode for VMESS share link
VMESS_BASE64=$(echo "$VMESS_CONFIG" | base64 -w 0)
VMESS_LINK="vmess://$VMESS_BASE64"

ok "VMESS configuration generated:"
kv "Server" "$PUBLIC_IP"
kv "Port" "443"
kv "UUID" "$VMESS_UUID"
kv "Security" "tls"

echo ""
echo "📋 VMESS Share Link:"
echo "$VMESS_LINK"
echo ""

# =================== Telegram Notification ===================
banner "📢 Step 8 — Telegram Notification"

if [[ -n "${TELEGRAM_TOKEN:-}" && ${#CHAT_ID_ARR[@]} -gt 0 ]]; then
  MSG=$(cat <<EOF
<pre>AWS VMESS + TLS DEPLOYED</pre>
<code>Address: ${PUBLIC_IP}</code>
<code>Port: 443</code>  
<code>UUID: ${VMESS_UUID}</code>
<code>Security: tls</code>

<blockquote>🔗 VMESS Link:</blockquote>
<code>${VMESS_LINK}</code>

<blockquote>⏰ Lab: Configure an Application Load Balancer with Autoscaling</blockquote>
<blockquote>🕒 Duration: 3 hours</blockquote>
EOF
)

  tg_send "${MSG}"
  ok "Telegram notification sent"
else
  warn "Telegram not configured - skipping notification"
fi

# =================== Final Instructions ===================
banner "✅ Deployment Complete"

echo "🎯 Next steps:"
echo "1. 📁 Upload scripts to your EC2 instances"
echo "2. 🔧 Run the installation script on each instance"  
echo "3. 🔒 Configure Load Balancer to forward port 443"
echo "4. 📱 Test the VMESS connection"
echo ""
echo "⏰ Lab Time: 3 hours"
echo "📄 Log file: $LOG_FILE"

printf "\n${C_GREEN}${BOLD}✨ AWS VMESS + TLS Deployment Ready!${RESET}\n"
echo "${C_GREY}Note: This script prepares configuration files. Manual EC2 setup required.${RESET}"
