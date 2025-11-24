#!/usr/bin/env bash
set -euo pipefail

# =================== 1. Rainbow UI & Animations ===================
# အရောင်စုံ Palette
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
BOLD='\033[1m'

# လန်းလန်းလေးဖြစ်စေမည့် Function များ
hr(){ printf "${PURPLE}%s${RESET}\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
banner(){ printf "\n${CYAN}${BOLD}✨ %s${RESET}\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n" "$1"; }
ok(){ printf "   ${GREEN}✔${RESET} %s\n" "$1"; }
kv(){ printf "   ${BLUE}➤ %-12s${RESET} ${WHITE}%s${RESET}\n" "$1" "$2"; }

# Loading Animation (Spinner)
run_with_progress() {
  local label="$1"; shift
  ( "$@" ) >/dev/null 2>&1 &
  local pid=$!
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  if [[ -t 1 ]]; then
    printf "\e[?25l"
    while kill -0 "$pid" 2>/dev/null; do
      i=$(( (i+1) %10 ))
      printf "\r   ${YELLOW}${spin:$i:1}${RESET} %s..." "$label"
      sleep 0.1
    done
    wait "$pid"
    printf "\r\e[K"
    printf "   ${GREEN}✅${RESET} %s\n" "$label"
    printf "\e[?25h"
  else
    wait "$pid"
  fi
}

clear
printf "\n${RED}${BOLD}🚀 ALPHA${YELLOW}0x1 ${BLUE}ULTRA ${PURPLE}(${CYAN}Premium gRPC${PURPLE})${RESET}\n"
hr

# =================== 2. Telegram Setup ===================
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

# =================== 3. Config & UUID ===================
banner "⚙️ Step 2 — Configuration"

# UUID အသစ်ထုတ်ခြင်း
GEN_UUID=$(cat /proc/sys/kernel/random/uuid)
kv "Mode" "gRPC Only (High Performance)"
kv "New UUID" "${GEN_UUID}"

SERVICE_NAME="alphas0x1"
REGION="us-central1"
IMAGE="a0x1/al0x1"
GRPC_SERVICE_NAME="Tg-@Alpha0x1"

# =================== 4. Deploying ===================
banner "🚀 Step 3 — Deploying to Cloud Run"

# Loading Animation နဲ့ Deploy လုပ်မယ်
run_with_progress "Pushing Container to Google Cloud" \
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

# Domain ပြန်ယူမယ်
URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}

banner "🎉 FINAL RESULT"
kv "Status" "Active"
kv "Domain" "${DOMAIN}"

# =================== 5. Notification ===================
banner "📨 Step 4 — Sending Notification"

# Link ထုတ်ခြင်း
URI="vless://${GEN_UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${DOMAIN}#Alpha0x1-gRPC"

# အချိန်သတ်မှတ်ခြင်း (Error မတက်အောင် START_LOCAL ပြန်သုံးထားသည်)
export TZ="Asia/Yangon"
START_LOCAL="$(date +'%d.%m.%Y %I:%M %p')"
END_LOCAL="$(date -d '+5 hours' +'%d.%m.%Y %I:%M %p')"

# မိတ်ဆွေ လိုချင်သော Message ပုံစံအတိုင်း (Copy/Paste)
MSG=$(cat <<EOF
<blockquote>🚀 Alpha0x1 V2RAY SERVICE</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<pre><code>${URI}</code></pre>

<blockquote>✅ စတင်ချိန်: <code>${START_LOCAL}</code></blockquote>
<blockquote>⏳ပြီးဆုံးအချိန်: <code>${END_LOCAL}</code></blockquote>
EOF
)

# ပို့မယ်
tg_send "${MSG}"

hr
printf "${GREEN}${BOLD}✅ ALL DONE! ENJOY YOUR SERVER.${RESET}\n"
