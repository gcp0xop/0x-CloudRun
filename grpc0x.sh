#!/usr/bin/env bash
set -euo pipefail

# =================== Minimal UI Colors ===================
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

# =================== Configuration ===================
SERVICE_NAME="alphas0x1"
REGION="us-central1"
IMAGE="a0x1/al0x1"
GRPC_SERVICE_NAME="Tg-@Alpha0x1"

clear
echo -e "${CYAN}🚀 ALPHA0x1 DEPLOYER (gRPC Edition)${RESET}"
echo "----------------------------------------"

# =================== 1. Telegram Setup ===================
if [[ -f .env ]]; then source ./.env; fi
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then read -rp "Enter Bot Token: " TELEGRAM_TOKEN; fi
if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then read -rp "Enter Chat ID:   " TELEGRAM_CHAT_IDS; fi

# =================== 2. Generate UUID ===================
UUID=$(cat /proc/sys/kernel/random/uuid)
echo -e "${YELLOW}➤ New UUID:${RESET} $UUID"

# =================== 3. Deploy to Cloud Run ===================
echo -e "${YELLOW}➤ Deploying to Cloud Run...${RESET}"

# Note: --use-http2 and --no-cpu-throttling are enabled for gRPC Stability
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
  --set-env-vars UUID="${UUID}" \
  --port="8080" \
  --min-instances=1 \
  --max-instances=2 \
  --quiet > /dev/null 2>&1

# Get Domain
URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}

echo -e "${GREEN}✔ Deployment Success!${RESET}"
echo -e "${CYAN}➤ Domain:${RESET} $DOMAIN"

# =================== 4. Generate Link & Notify ===================
# gRPC Link Format
URI="vless://${UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${DOMAIN}#Alpha0x1"

# Time Setup
export TZ="Asia/Yangon"
START_TIME="$(date +'%I:%M %p')"
END_TIME="$(date -d '+5 hours' +'%I:%M %p')"

# Telegram Message
MSG=$(cat <<EOF
<blockquote>🚀 Alpha0x1 V2RAY SERVICE</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<pre><code>${URI}</code></pre>

<blockquote>✅စတင်ချိန်: <code>${START_LOCAL}</code></blockquote>
<blockquote>⏳ပြီးဆုံးအချိန်: <code>${END_LOCAL}</code></blockquote>
EOF
)

tg_send "${MSG}"

# Send Notification
if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_IDS" ]]; then
  IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
  for chat_id in "${CHAT_ID_ARR[@]}"; do
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${chat_id}" \
      -d "parse_mode=HTML" \
      --data-urlencode "text=${MSG}" > /dev/null
    echo -e "${GREEN}✔ Sent to ID: ${chat_id}${RESET}"
  done
else
  echo -e "${RED}⚠ Notification skipped (No Token)${RESET}"
fi

echo "----------------------------------------"
echo -e "${GREEN}DONE.${RESET}"
