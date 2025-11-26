#!/usr/bin/env bash
set -euo pipefail

# =================== 1. UI Colors ===================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
BOLD='\033[1m'

clear
printf "\n${RED}${BOLD}🚀 ALPHA${YELLOW}0x1 ${BLUE}INFINITY ${PURPLE}(${CYAN}The Final Boss${PURPLE})${RESET}\n"
printf "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

# =================== 2. Setup ===================
if [[ -f .env ]]; then source ./.env; fi

if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then 
  printf "   ${CYAN}💎 Bot Token:${RESET} "
  read -r TELEGRAM_TOKEN
fi

if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then 
  printf "   ${CYAN}💎 Chat ID:${RESET}   "
  read -r TELEGRAM_CHAT_IDS
fi

# =================== 3. Config ===================
# Auto-Counter Logic
COUNT_FILE=".alpha_counter"
if [[ ! -f "$COUNT_FILE" ]]; then echo "0" > "$COUNT_FILE"; fi
CURRENT_COUNT=$(<"$COUNT_FILE")
NEXT_COUNT=$((CURRENT_COUNT + 1))
echo "$NEXT_COUNT" > "$COUNT_FILE"

SUFFIX=$(printf "%03d" "$NEXT_COUNT")
SERVER_NAME="Alpha0x1-${SUFFIX}"
GEN_UUID=$(cat /proc/sys/kernel/random/uuid)

SERVICE_NAME="alphas0x1"
REGION="us-central1"
IMAGE="a0x1/al0x1"
GRPC_SERVICE_NAME="Tg-@Alpha0x1"

# =================== 4. Deploying ===================
echo ""
echo -e "${YELLOW}➤ Deploying Infinity Node (${SERVER_NAME})...${RESET}"

# Enable API quietly
gcloud services enable run.googleapis.com --quiet >/dev/null 2>&1

# Deploy Command (THE PERFECT COMBO)
# 4 vCPU + 4GB + Gen2 + NoThrottle + Multi-Path Tags
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
  --execution-environment=gen2 \
  --concurrency=1000 \
  --session-affinity \
  --labels="tier=platinum,mode=infinity" \
  --tag="vip" \
  --set-env-vars UUID="${GEN_UUID}" \
  --port="8080" \
  --min-instances=1 \
  --max-instances=2 \
  --quiet

# Get Domain
URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}
VIP_DOMAIN="vip---${DOMAIN}"

# Warm up
curl -s -o /dev/null "https://${DOMAIN}"

# =================== 5. Notification ===================
echo -e "${YELLOW}➤ Generating Infinity Links...${RESET}"

export TZ="Asia/Yangon"
START_LOCAL="$(date +'%d.%m.%Y %I:%M %p')"
END_LOCAL="$(date -d '+5 hours 10 minutes' +'%d.%m.%Y %I:%M %p')"

# 1. Classic (Stable)
URI_CLASSIC="vless://${GEN_UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${DOMAIN}#${SERVER_NAME}-Classic"

# 2. Download (High Speed - VIP Path)
URI_DL="vless://${GEN_UUID}@dl.google.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${VIP_DOMAIN}#${SERVER_NAME}-Speed"

# 3. DNS (Gaming - VIP Path)
URI_DNS="vless://${GEN_UUID}@dns.google:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${VIP_DOMAIN}#${SERVER_NAME}-Ping"

# 4. API (Backup)
URI_API="vless://${GEN_UUID}@www.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${DOMAIN}#${SERVER_NAME}-API"

MSG="<blockquote>🚀 ${SERVER_NAME} INFINITY</blockquote>
<blockquote>⚡ 4-Core / 4GB / No-Throttle</blockquote>
<blockquote>⏰ 5-Hour 10-Min Free Service</blockquote>

<b>💎 SPEED LINK (Recommend):</b>
<pre><code>${URI_DL}</code></pre>

<b>🛡️ CLASSIC LINK:</b>
<pre><code>${URI_CLASSIC}</code></pre>

<b>🎮 GAMING LINK:</b>
<pre><code>${URI_DNS}</code></pre>

<blockquote>✅ Start: <code>${START_LOCAL}</code></blockquote>
<blockquote>⏳ End: <code>${END_LOCAL}</code></blockquote>"

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
  printf "${RED}⚠ No Token found.${RESET}\n"
fi

# =================== Final Report ===================
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════╗${RESET}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Name" "${SERVER_NAME}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Config" "Infinity (No-Throttle)"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Links" "4 Paths Generated"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${GREEN}%-20s${RESET} ${YELLOW}║${RESET}\n" "Status" "Active ✅"
echo -e "${YELLOW}╚════════════════════════════════════════════╝${RESET}"
echo ""
