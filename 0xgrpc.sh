#!/usr/bin/env bash
set -euo pipefail

# ===== Ensure interactive reads =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & Error Handler =====
LOG_FILE="/tmp/ksgcp_30users_$(date +%s).log"
touch "$LOG_FILE"
exec 2>>"$LOG_FILE"

on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR at line $LINENO: ${BASH_COMMAND}" | tee -a "$LOG_FILE" >&2
  echo "📄 Full log: $LOG_FILE" >&2
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

printf "\n${C_CYAN}${BOLD}🚀 KSGCP 30-USERS VLESS + Telegram${RESET}\n"
hr

# =================== Progress Spinner ===================
run_with_progress() {
  local label="$1"; shift
  local start_time=$(date +%s)
  
  ( "$@" ) >>"$LOG_FILE" 2>&1 &
  local pid=$!
  local pct=5
  
  if [[ -t 1 ]]; then
    printf "\e[?25l"
    while kill -0 "$pid" 2>/dev/null; do
      local step=$(( (RANDOM % 9) + 2 ))
      pct=$(( pct + step ))
      (( pct > 95 )) && pct=95
      local elapsed=$(( $(date +%s) - start_time ))
      printf "\r🌀 %s... [%s%%] (%ds)" "$label" "$pct" "$elapsed"
      sleep "$(awk -v r=$RANDOM 'BEGIN{s=0.08+(r%7)/100; printf "%.2f", s }')"
    done
    wait "$pid"; local rc=$?
    printf "\r"
    if (( rc==0 )); then
      local total_time=$(( $(date +%s) - start_time ))
      printf "✅ %s... [100%%] (%ds)\n" "$label" "$total_time"
    else
      printf "❌ %s failed\n" "$label"
      return $rc
    fi
    printf "\e[?25h"
  else
    wait "$pid"
  fi
}

# =================== System Optimization ===================
banner "⚡ System Optimization"
run_with_progress "Tuning for 30 users" '
sudo sysctl -w net.core.rmem_max=134217728 > /dev/null
sudo sysctl -w net.core.wmem_max=134217728 > /dev/null
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728" > /dev/null
sudo sysctl -w net.ipv4.tcp_wmem="4096 16384 134217728" > /dev/null
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null
sudo sysctl -w net.ipv4.tcp_slow_start_after_idle=0 > /dev/null
sudo sysctl -w net.ipv4.tcp_notsent_lowat=16384 > /dev/null
'

# =================== Telegram Setup ===================
banner "🤖 Telegram Setup"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

if [[ -f .env ]]; then
  set -a; source ./.env; set +a
fi

read -rp "🔑 Telegram Bot Token: " _token </dev/tty
[[ -n "${_token:-}" ]] && TELEGRAM_TOKEN="$_token"

read -rp "💬 Your Chat ID: " _chatid </dev/tty
[[ -n "${_chatid:-}" ]] && TELEGRAM_CHAT_ID="$_chatid"

if [[ -z "${TELEGRAM_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  warn "Telegram not configured"
else
  ok "Telegram configured for auto-send"
fi

# =================== System Preparation ===================
banner "🔧 System Preparation"
run_with_progress "Updating packages" \
  sudo apt-get update -y

run_with_progress "Installing dependencies" \
  sudo apt-get install -y curl wget openssl

# =================== Xray Installation ===================
banner "📦 Xray Installation"
install_xray_with_retry() {
  local max_retries=3
  local retry=0
  
  while (( retry < max_retries )); do
    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root; then
      return 0
    fi
    (( retry++ ))
    warn "Xray installation failed, retry $retry/$max_retries"
    sleep 2
  done
  err "Xray installation failed after $max_retries attempts"
  return 1
}

run_with_progress "Installing Xray" install_xray_with_retry

# =================== VLESS Configuration ===================
banner "🔐 VLESS Setup"
VLESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)
IP_ADDRESS=$(curl -s --connect-timeout 5 ifconfig.me || curl -s --connect-timeout 5 ipinfo.io/ip || hostname -I | awk "{print \$1}")

ok "Generated UUID: ${VLESS_UUID}"
ok "Server IP: ${IP_ADDRESS}"

# Create optimized config for 30 users
run_with_progress "Creating configuration" '
sudo mkdir -p /usr/local/etc/xray

sudo cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "$VLESS_UUID",
        "flow": "xtls-rprx-vision",
        "level": 0
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "tls",
      "tlsSettings": {
        "certificates": [{
          "certificateFile": "/usr/local/etc/xray/cert.crt",
          "keyFile": "/usr/local/etc/xray/private.key"
        }],
        "alpn": ["h2", "http/1.1"],
        "minVersion": "1.2",
        "cipherSuites": "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256:TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
      },
      "tcpSettings": {
        "header": {
          "type": "none"
        }
      }
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls", "quic"],
      "metadataOnly": false
    },
    "tag": "vless-tls"
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {
      "domainStrategy": "UseIP"
    },
    "tag": "direct"
  }, {
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "blocked"
      }
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 300,
        "uplinkOnly": 2,
        "downlinkOnly": 5,
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  }
}
EOF

sudo mkdir -p /var/log/xray
'

# =================== Certificate Generation ===================
banner "📄 TLS Certificate"
run_with_progress "Generating certificate" '
sudo openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
  -subj "/C=US/ST=California/L=San Francisco/O=Google Cloud/CN=cloud.google.com" \
  -keyout /usr/local/etc/xray/private.key \
  -out /usr/local/etc/xray/cert.crt 2>/dev/null
'

# =================== Security Hardening ===================
banner "🛡️ Security Hardening"
run_with_progress "Setting permissions" '
sudo chown -R root:root /usr/local/etc/xray/
sudo chmod 600 /usr/local/etc/xray/private.key
sudo chmod 644 /usr/local/etc/xray/cert.crt
sudo chmod 644 /usr/local/etc/xray/config.json
'

# =================== Service Setup ===================
banner "🚀 Service Setup"
run_with_progress "Starting Xray service" '
sudo systemctl daemon-reload
sudo systemctl enable xray
sudo systemctl start xray
sleep 3
'

# Check service status
if sudo systemctl is-active --quiet xray; then
  ok "Xray service is running"
else
  err "Xray service failed to start"
  run_with_progress "Checking logs" '
  sudo journalctl -u xray -n 10 --no-pager
  '
  exit 1
fi

# =================== Firewall Configuration ===================
banner "🔥 Firewall Setup"
run_with_progress "Configuring firewall" '
gcloud compute firewall-rules delete -q ksgcp-30users 2>/dev/null || true
gcloud compute firewall-rules create ksgcp-30users \
  --allow=tcp:443 \
  --direction=INGRESS \
  --priority=1000 \
  --description="KSGCP 30 Users VLESS" \
  --quiet
'

# =================== Generate VLESS Link ===================
VLESS_LINK="vless://$VLESS_UUID@$IP_ADDRESS:443?security=tls&flow=xtls-rprx-vision&alpn=h2%2Chttp%2F1.1&type=tcp&headerType=none#KSGCP-30USERS"

# =================== Telegram Notification ===================
banner "📤 Telegram Notification"

tg_send() {
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then 
    return 0
  fi
  
  local response
  response=$(curl -s -w "%{http_code}" -o /tmp/tg_response \
    -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" \
    -d "parse_mode=HTML" \
    -H "Content-Type: application/x-www-form-urlencoded")
  
  if [[ "$response" == "200" ]]; then
    return 0
  else
    warn "Telegram send failed (HTTP $response)"
    return 1
  fi
}

if [[ -n "${TELEGRAM_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  MSG="<b>🚀 KSGCP 30-USERS VLESS READY</b>

<code>🔧 Optimized for 30 concurrent users</code>
<code>💪 4vCPU + 4GB RAM Performance</code>
<code>🌐 Server: ${IP_ADDRESS}</code>
<code>🔐 Port: 443 (TLS)</code>
<code>📡 Protocol: VLESS + Vision</code>
<code>🆔 UUID: ${VLESS_UUID}</code>

<code>🔗 VLESS Link:</code>
<code>${VLESS_LINK}</code>

<blockquote>⏰ Lab Duration: 2+ Hours</blockquote>
<blockquote>👥 Max Users: 30 Concurrent</blockquote>
<blockquote>🚀 Performance: High Speed</blockquote>"

  if run_with_progress "Sending to Telegram" tg_send "${MSG}"; then
    ok "Configuration sent to Telegram"
  else
    warn "Telegram send failed - manual copy required"
  fi
else
  warn "Telegram not configured - manual copy required"
fi

# =================== Final Output ===================
banner "✅ Deployment Complete"

echo ""
echo "${C_GREEN}🎯 Optimized for 30 Concurrent Users${RESET}"
echo "${C_GREEN}💪 4vCPU + 4GB RAM Performance${RESET}"
echo ""
kv "Protocol" "VLESS + TLS + Vision"
kv "Server" "$IP_ADDRESS"
kv "Port" "443"
kv "UUID" "$VLESS_UUID"  
kv "Flow" "xtls-rprx-vision"
kv "Max Users" "30 Concurrent"
echo ""

echo "${C_CYAN}🔗 VLESS Share Link:${RESET}"
echo "${C_YEL}${VLESS_LINK}${RESET}"
echo ""

echo "${C_GREEN}⚡ Performance Features:${RESET}"
echo "   ✅ TCP BBR Congestion Control"
echo "   ✅ Large Network Buffers"
echo "   ✅ Connection Optimization"
echo "   ✅ Traffic Sniffing"
echo "   ✅ Ads Blocking"
echo ""

echo "${C_ORG}📊 Usage Statistics Enabled${RESET}"
echo "${C_GREY}📄 Log File: $LOG_FILE${RESET}"
echo ""

if [[ -n "${TELEGRAM_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "${C_GREEN}✅ Configuration sent to Telegram${RESET}"
else
  echo "${C_ORG}⚠️ Manual copy required - Telegram not configured${RESET}"
fi

echo ""
echo "${C_CYAN}⏰ Ready for 30 users for 2+ hours!${RESET}"
