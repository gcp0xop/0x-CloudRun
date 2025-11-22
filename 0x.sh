#!/usr/bin/env bash
set -euo pipefail

# =================== 1. Setup & UI ===================
# Logging
LOG_FILE="/tmp/alpha0x1_deploy.log"
echo "" > "$LOG_FILE"

# Error Handler
on_err() {
  echo ""
  echo "❌ ERROR: Command failed. See logs below:"
  tail -n 20 "$LOG_FILE"
  exit 1
}
trap on_err ERR

# Colors
C_GOLD=$'\e[38;5;220m'
C_LIME=$'\e[38;5;118m'
C_RED=$'\e[38;5;196m'
C_GREY=$'\e[38;5;240m'
RESET=$'\e[0m'

banner() {
  printf "\n${C_GOLD}✨ %s${RESET}\n${C_GREY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n" "$1"
}
ok() { printf "   ${C_LIME}✔${RESET} %s\n" "$1"; }

clear
printf "\n${C_GOLD}🚀 Alpha0x1 CLOUD RUN DEPLOYER${RESET} (Clean Version)\n"
printf "${C_GREY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

# =================== 2. Configuration ===================
# --- Telegram ---
banner "🤖 Telegram Setup"
if [[ -f .env ]]; then source .env; fi
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-}"

if [[ -z "$TELEGRAM_TOKEN" ]]; then
    read -rp "   ${C_GOLD}💎 Bot Token:${RESET} " TELEGRAM_TOKEN
fi
if [[ -z "$TELEGRAM_CHAT_IDS" ]]; then
    read -rp "   ${C_GOLD}💎 Chat ID:${RESET}   " TELEGRAM_CHAT_IDS
fi

# --- Project Check ---
PROJECT="$(gcloud config get-value project 2>/dev/null)"
if [[ -z "$PROJECT" ]]; then
  echo "${C_RED}❌ No Active Project found! Run: gcloud config set project ID${RESET}"
  exit 1
fi

# =================== 3. Protocol Selection ===================
banner "🔌 Protocol Selection"
echo "   1. Trojan WS"
echo "   2. VLESS WS"
echo "   3. VLESS gRPC (Recommended)"
read -rp "   ${C_GOLD}Select [1-3]:${RESET} " _opt

case "${_opt:-3}" in
  1) 
     PROTO="trojan-ws"
     IMAGE="docker.io/n4pro/tr:latest"
     ARGS="" 
     ;;
  2) 
     PROTO="vless-ws"
     IMAGE="docker.io/n4pro/vl:latest"
     ARGS="" 
     ;;
  *) 
     PROTO="vless-grpc"
     IMAGE="docker.io/n4pro/vl:latest"
     # gRPC requires HTTP/2
     ARGS="--use-http2" 
     ;;
esac
ok "Selected: ${PROTO^^}"

# =================== 4. Deployment ===================
banner "🚀 Deploying to Cloud Run..."

SERVICE="alpha0x1"
REGION="us-central1"

# Resource Config (Safe for Quota: Total 8 CPU)
CPU="4"
MEMORY="4Gi"
MAX_INSTANCES="2"
CONCURRENCY="300"

echo "   ... Please wait (approx 1-2 mins) ..."

# Deploy Command
gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --timeout=3600 \
  --allow-unauthenticated \
  --port=8080 \
  --min-instances=1 \
  --max-instances="$MAX_INSTANCES" \
  --concurrency="$CONCURRENCY" \
  $ARGS \
  --quiet >> "$LOG_FILE" 2>&1

ok "Deployment Successful!"

# Get URL
URL=$(gcloud run services describe "$SERVICE" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN="${URL#https://}"

# =================== 5. Generate Link ===================
# UUID / Password (Using openssl to avoid error 141)
UUID=$(cat /proc/sys/kernel/random/uuid)
PASSWORD=$(openssl rand -hex 6)

case "$PROTO" in
  trojan-ws)
    LINK="trojan://${PASSWORD}@vpn.googleapis.com:443?path=%2FN4&security=tls&host=${DOMAIN}&type=ws#Alpha0x1"
    ;;
  vless-ws)
    LINK="vless://${UUID}@vpn.googleapis.com:443?path=%2FN4&security=tls&encryption=none&host=${DOMAIN}&type=ws#Alpha0x1"
    ;;
  vless-grpc)
    # gRPC Link Format
    LINK="vless://${UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=n4-grpc&sni=${DOMAIN}#Alpha0x1"
    ;;
esac

# =================== 6. Notify & Finish ===================
# Time Setup
export TZ="Asia/Yangon"
START_TIME="$(date '+%d.%m.%Y %I:%M %p')"
END_TIME="$(date -d '+5 hours' '+%d.%m.%Y %I:%M %p')"

# Custom Message as requested
MSG=$(cat <<EOF
<b>🚀 Alpha0x1 V2RAY SERVICE</b>
<b>⏰ 5-Hour Free Service</b>
<b>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</b>
<pre><code>${LINK}</code></pre>

✅ စတင်ချိန်: <code>${START_TIME}</code>
⏳ပြီးဆုံးချိန်: <code>${END_TIME}</code>
EOF
)

# Send to Telegram
IFS=',' read -r -a CHAT_ARR <<< "${TELEGRAM_CHAT_IDS// /}"
for chat_id in "${CHAT_ARR[@]}"; do
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        -d "text=${MSG}" \
        -d "parse_mode=HTML" > /dev/null
done

banner "🎉 COMPLETED"
ok "Link sent to Telegram."
echo ""
echo "${C_GOLD}COPY YOUR LINK HERE:${RESET}"
echo "$LINK"
echo ""
