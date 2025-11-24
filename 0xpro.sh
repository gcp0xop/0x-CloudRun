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
printf "\n${RED}${BOLD}🚀 ALPHA${YELLOW}0x1 ${BLUE}CEO EDITION ${PURPLE}(${CYAN}Stable${PURPLE})${RESET}\n"
hr

# =================== 2. Setup (Fixed UI) ===================
banner "🤖 Step 1 — Setup"

if [[ -f .env ]]; then source ./.env; fi

# Fixed: Using printf to show colors correctly before reading input
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then 
  printf "   ${CYAN}💎 Bot Token:${RESET} "
  read -r TELEGRAM_TOKEN
fi

if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then 
  printf "   ${CYAN}💎 Chat ID:${RESET}   "
  read -r TELEGRAM_CHAT_IDS
fi

# =================== 3. Config & Counter ===================
banner "⚙️ Step 2 — Configuration"

# Auto-Counter Logic
COUNT_FILE=".alpha_counter"
if [[ ! -f "$COUNT_FILE" ]]; then echo "0" > "$COUNT_FILE"; fi
CURRENT_COUNT=$(<"$COUNT_FILE")
NEXT_COUNT=$((CURRENT_COUNT + 1))
echo "$NEXT_COUNT" > "$COUNT_FILE"

SUFFIX=$(printf "%03d" "$NEXT_COUNT")
SERVER_NAME="Alpha0x1-${SUFFIX}"

GEN_UUID=$(cat /proc/sys/kernel/random/uuid)

kv "Mode" "CEO (Gen2 + High Stability)"
kv "UUID" "${GEN_UUID}"
kv "Name" "${SERVER_NAME}"

SERVICE_NAME="alphas0x1"
REGION="us-central1"
IMAGE="a0x1/al0x1"
GRPC_SERVICE_NAME="Tg-@Alpha0x1"

# =================== 4. Deploying ===================
banner "🚀 Step 3 — Deploying"

# Clean up old service
if gcloud run services describe "$SERVICE_NAME" --region "$REGION" >/dev/null 2>&1; then
    run_with_progress "Cleaning workspace..." \
    gcloud run services delete "$SERVICE_NAME" --region "$REGION" --quiet
fi

# Deploy with STABLE High-Performance Flags (Removed beta/boost flags that cause hangs)
run_with_progress "Executing Deployment..." \
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

URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}

run_with_progress "System Warm-up..." \
  curl -s -o /dev/null "https://${DOMAIN}"

# =================== 5. Notification ===================
banner "📨 Step 4 — Notification"

URI="vless://${GEN_UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${DOMAIN}#${SERVER_NAME}"

export TZ="Asia/Yangon"
START_LOCAL="$(date +'%d.%m.%Y %I:%M %p')"
END_LOCAL="$(date -d '+5 hours' +'%d.%m.%Y %I:%M %p')"

MSG=$(cat <<EOF
<blockquote>🚀 ${SERVER_NAME} SERVICE</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡 Unlimited Data / Bypass Restricted Areas</blockquote>
<pre><code>${URI}</code></pre>

<blockquote>✅ Start: <code>${START_LOCAL}</code></blockquote>
<blockquote>⏳ End: <code>${END_LOCAL}</code></blockquote>
EOF
)

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
  printf "   ${YELLOW}⚠ Notification skipped.${RESET}\n"
fi

# =================== CEO DASHBOARD ===================
clear
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════╗${RESET}"
echo -e "${YELLOW}║          EXECUTIVE SYSTEM REPORT           ║${RESET}"
echo -e "${YELLOW}╠════════════════════════════════════════════╣${RESET}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Service Name" "${SERVER_NAME}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Region" "${REGION}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Engine" "Gen2 (Stable)"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Memory" "4Gi / 4 vCPU"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${GREEN}%-20s${RESET} ${YELLOW}║${RESET}\n" "Status" "Active"
echo -e "${YELLOW}╚════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${GREEN}${BOLD}   MISSION COMPLETE. SYSTEM ONLINE.${RESET}"
echo ""
