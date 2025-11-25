#!/usr/bin/env bash
set -euo pipefail

# =================== 1. UI & Colors ===================
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
printf "\n${RED}${BOLD}🚀 ALPHA${YELLOW}0x1 ${BLUE}CEO EDITION ${PURPLE}(${CYAN}Final Perfect${PURPLE})${RESET}\n"
hr

# =================== 2. Setup ===================
banner "🤖 Step 1 — Setup"

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
banner "⚙️ Step 2 — Configuration"

# Auto-Counter
COUNT_FILE=".alpha_counter"
if [[ ! -f "$COUNT_FILE" ]]; then echo "0" > "$COUNT_FILE"; fi
CURRENT_COUNT=$(<"$COUNT_FILE")
NEXT_COUNT=$((CURRENT_COUNT + 1))
echo "$NEXT_COUNT" > "$COUNT_FILE"

SUFFIX=$(printf "%03d" "$NEXT_COUNT")
SERVER_NAME="Alpha0x1-${SUFFIX}"
GEN_UUID=$(cat /proc/sys/kernel/random/uuid)

kv "Mode" "CEO (4 vCPU / 4GB RAM)"
kv "UUID" "${GEN_UUID}"
kv "Name" "${SERVER_NAME}"

SERVICE_NAME="alphas0x1"
REGION="us-central1"
IMAGE="a0x1/al0x1"
GRPC_SERVICE_NAME="Tg-@Alpha0x1"

# =================== 4. Deploying ===================
banner "🚀 Step 3 — Deploying"

# Enable API
echo -e "${YELLOW}➤ Checking APIs...${RESET}"
gcloud services enable run.googleapis.com --quiet >/dev/null 2>&1

# Deploy Command
echo -e "${YELLOW}➤ Starting Deployment...${RESET}"
echo "---------------------------------------------------"

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
  --set-env-vars UUID="${GEN_UUID}" \
  --port="8080" \
  --min-instances=1 \
  --max-instances=2 \
  --quiet

echo "---------------------------------------------------"

# Get Domain
URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}

# Warm up
curl -s -o /dev/null "https://${DOMAIN}"

# =================== 5. Notification ===================
banner "📨 Step 4 — Notification"

URI="vless://${GEN_UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${DOMAIN}#${SERVER_NAME}"

export TZ="Asia/Yangon"
START_LOCAL="$(date +'%d.%m.%Y %I:%M %p')"
END_LOCAL="$(date -d '+5 hours' +'%d.%m.%Y %I:%M %p')"

# 🔥 FIXED MSG: Using pure string concatenation (No Backticks)
MSG="<b>🚀 ${SERVER_NAME} SERVICE</b>%0A"
MSG+="⏰ 5-Hour Free Service%0A"
MSG+="📡 Unlimited Data / Bypass Restricted Areas%0A"
MSG+="<pre>${URI}</pre>%0A"
MSG+="✅ Start: ${START_LOCAL}%0A"
MSG+="⏳ End: ${END_LOCAL}"

if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_IDS" ]]; then
  IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
  for chat_id in "${CHAT_ID_ARR[@]}"; do
    # Using direct text passing instead of data-urlencode for safety
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${chat_id}" \
      -d "parse_mode=HTML" \
      -d "text=${MSG}" > /dev/null
    ok "Sent to ID: ${chat_id}"
  done
else
  printf "   ${YELLOW}⚠ Notification skipped.${RESET}\n"
fi

# =================== CEO DASHBOARD ===================
clear
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════╗${RESET}"
echo -e "${YELLOW}║          EXECUTIVE SYSTEM REPORT           ║${RESET}"
echo -e "${YELLOW}╠════════════════════════════════════════════╣${RESET}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Service Name" "${SERVER_NAME}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Specs" "4 vCPU / 4Gi RAM"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "UUID" "...${GEN_UUID: -6}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${GREEN}%-20s${RESET} ${YELLOW}║${RESET}\n" "Status" "Active"
echo -e "${YELLOW}╚════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${GREEN}${BOLD}   DEPLOYMENT SUCCESSFUL.${RESET}"
echo ""
