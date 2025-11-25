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

# Minimal & Clean Header
header() {
    clear
    echo -e "${PURPLE}╔════════════════════════════════════════════╗${RESET}"
    echo -e "${PURPLE}║${RESET}       ${RED}${BOLD}🚀 ALPHA${YELLOW}0x1 ${BLUE}PREMIUM SERVER${RESET}         ${PURPLE}║${RESET}"
    echo -e "${PURPLE}╚════════════════════════════════════════════╝${RESET}"
    echo ""
}

# Helper Functions
step() { echo -e "\n${CYAN}${BOLD}✨ $1${RESET}\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
ok() { echo -e "   ${GREEN}✔${RESET} $1"; }
info() { echo -e "   ${BLUE}➤${RESET} $1"; }

header

# =================== 2. Setup Phase ===================
step "Step 1: Setup"

if [[ -f .env ]]; then source ./.env; fi

if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then 
  printf "   ${YELLOW}🔑 Bot Token:${RESET} "
  read -r TELEGRAM_TOKEN
fi

if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then 
  printf "   ${YELLOW}💬 Chat ID:${RESET}   "
  read -r TELEGRAM_CHAT_IDS
fi

# =================== 3. Configuration ===================
step "Step 2: Configuration"

# Auto-Counter Logic
COUNT_FILE=".alpha_counter"
if [[ ! -f "$COUNT_FILE" ]]; then echo "0" > "$COUNT_FILE"; fi
CURRENT_COUNT=$(<"$COUNT_FILE")
NEXT_COUNT=$((CURRENT_COUNT + 1))
echo "$NEXT_COUNT" > "$COUNT_FILE"

SUFFIX=$(printf "%03d" "$NEXT_COUNT")
SERVER_NAME="Alpha0x1-${SUFFIX}"
GEN_UUID=$(cat /proc/sys/kernel/random/uuid)

# Specs
SERVICE_NAME="alphas0x1"
REGION="us-central1"
IMAGE="a0x1/al0x1"
GRPC_SERVICE_NAME="Tg-@Alpha0x1"

info "${WHITE}Name:${RESET}   ${GREEN}${SERVER_NAME}${RESET}"
info "${WHITE}Engine:${RESET} ${GREEN}Gen2 (Max Speed)${RESET}"
info "${WHITE}Specs:${RESET}  ${GREEN}4 vCPU / 4GB RAM${RESET}"

# =================== 4. Deploying ===================
step "Step 3: Deploying..."

# Enable API quietly
gcloud services enable run.googleapis.com --quiet >/dev/null 2>&1

echo -e "${YELLOW}   🚀 Launching High-Performance Node...${RESET}"
echo "---------------------------------------------------"

# Deploy Command (Gen2 + Max Specs)
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
step "Step 4: Sending Key"

URI="vless://${GEN_UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${DOMAIN}#${SERVER_NAME}"

export TZ="Asia/Yangon"
START_LOCAL="$(date +'%d.%m.%Y %I:%M %p')"
END_LOCAL="$(date -d '+5 hours' +'%d.%m.%Y %I:%M %p')"

# Telegram Message
MSG="<blockquote>🚀 ${SERVER_NAME} V2RAY SERVICE</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<pre><code>${URI}</code></pre>
<blockquote>✅ စတင်ချိန်: <code>${START_LOCAL}</code></blockquote>
<blockquote>⏳ပြီးဆုံးအချိန်: <code>${END_LOCAL}</code></blockquote>"

if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_IDS" ]]; then
  IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
  for chat_id in "${CHAT_ID_ARR[@]}"; do
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${chat_id}" \
      -d "parse_mode=HTML" \
      --data-urlencode "text=${MSG}" > /dev/null
    ok "Sent to ID: ${chat_id}"
  done
else
  printf "   ${RED}⚠ Notification skipped.${RESET}\n"
fi

# =================== 6. Final Status ===================
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════╗${RESET}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Server Name" "${SERVER_NAME}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${GREEN}%-20s${RESET} ${YELLOW}║${RESET}\n" "Status" "Active ✅"
echo -e "${YELLOW}╚════════════════════════════════════════════╝${RESET}"
echo ""
