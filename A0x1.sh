#!/usr/bin/env bash
set -euo pipefail

# =================== UI Colors ===================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
BOLD='\033[1m'

hr(){ printf "${PURPLE}%s${RESET}\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
banner(){ printf "\n${CYAN}${BOLD}✨ %s${RESET}\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n" "$1"; }
ok(){ printf "   ${GREEN}✔${RESET} %s\n" "$1"; }
kv(){ printf "   ${BLUE}➤ %-12s${RESET} ${WHITE}%s${RESET}\n" "$1" "$2"; }

clear
printf "\n${RED}${BOLD}🚀 ALPHA${YELLOW}0x1 ${BLUE}PERFORMANCE ${PURPLE}(${CYAN}Anti-Lag${PURPLE})${RESET}\n"
hr

# =================== Telegram Setup ===================
banner "🤖 Step 1 — Telegram Setup"
if [[ -f .env ]]; then source ./.env; fi
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then read -rp "   ${CYAN}💎 Bot Token:${RESET} " TELEGRAM_TOKEN; fi
if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then read -rp "   ${CYAN}💎 Chat ID:${RESET}   " TELEGRAM_CHAT_IDS; fi

tg_send(){
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || -z "${TELEGRAM_CHAT_IDS:-}" ]]; then return 0; fi
  IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" > /dev/null
    ok "Sent to ID: ${_cid}"
  done
}

# =================== Generate UUID ===================
banner "🎲 Step 2 — Generating Credentials"
GEN_UUID=$(cat /proc/sys/kernel/random/uuid)
kv "New UUID" "${GEN_UUID}"

# =================== Cloud Run Deploy ===================
banner "🚀 Step 3 — Deploying (High Performance Mode)"

IMAGE="a0x1/al0x1"
SERVICE_NAME="alphas0x1"
REGION="us-central1"
COMMON_PATH="Tg-@Alpha0x1"

# 🔥 အဓိက ပြင်ဆင်ချက်: --no-cpu-throttling ထည့်ထားသည်
gcloud run deploy "$SERVICE_NAME" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="4Gi" \
  --cpu="4" \
  --timeout="3600" \
  --allow-unauthenticated \
  --use-http2 \
  --no-cpu-throttling \
  --set-env-vars UUID="${GEN_UUID}" \
  --port="8080" \
  --min-instances=1 \
  --max-instances=2 \
  --quiet

URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}

banner "🎉 FINAL RESULT"
kv "Domain" "${DOMAIN}"

# =================== Link Generation ===================
URI_WS="vless://${GEN_UUID}@vpn.googleapis.com:443?security=tls&encryption=none&host=${DOMAIN}&type=ws&path=%2F${COMMON_PATH}#Alpha0x1-WS"
URI_GRPC="vless://${GEN_UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${COMMON_PATH}&sni=${DOMAIN}#Alpha0x1-gRPC"

# =================== Telegram Notify ===================
banner "📨 Step 4 — Sending Notification"

export TZ="Asia/Yangon"
START_TIME="$(date +'%d.%m.%Y %I:%M %p')"
END_TIME="$(date -d '+5 hours' +'%d.%m.%Y %I:%M %p')"

MSG=$(cat <<EOF
<blockquote>🚀 Alpha0x1 V2RAY SERVICE </blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<b>💎 VLESS WebSocket (WS):</b>
<pre><code>${URI_WS}</code></pre>

<b>💎 VLESS gRPC:</b>
<pre><code>${URI_GRPC}</code></pre>

<blockquote>✅ စတင်ချိန်: <code>${START_TIME}</code></blockquote>
<blockquote>⏳ပြီးဆုံးအချိန်: <code>${END_TIME}</code></blockquote>
EOF
)

tg_send "${MSG}"
printf "\n${GREEN}${BOLD}✅ ALL DONE! Service deployed with CPU Boost.${RESET}\n"
