#!/usr/bin/env bash
set -euo pipefail

# ===== Ensure interactive reads =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & Error Handler =====
LOG_FILE="/tmp/alpha0x1_deploy_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  printf "\n\033[1;31m❌ ERROR: Command failed (exit %d). See log: %s\033[0m\n" "$rc" "$LOG_FILE" >&2
  exit $rc
}
trap on_err ERR

# =================== Color & UI (Colorful Theme) ===================
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
warn(){ printf "   ${YELLOW}⚠${RESET} %s\n" "$1"; }
kv(){ printf "   ${BLUE}➤ %-12s${RESET} ${WHITE}%s${RESET}\n" "$1" "$2"; }

clear
printf "\n${RED}${BOLD}🚀 ALPHA${YELLOW}0x1 ${BLUE}DEPLOYER ${PURPLE}(${CYAN}Premium Edition${PURPLE})${RESET}\n"
hr

# =================== Spinner Function ===================
run_with_progress() {
  local label="$1"; shift
  ( "$@" ) >>"$LOG_FILE" 2>&1 &
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
    wait "$pid"; local rc=$?
    printf "\r\e[K"
    if (( rc==0 )); then
      printf "   ${GREEN}✅${RESET} %s\n" "$label"
    else
      printf "   ${RED}❌${RESET} %s failed\n" "$label"
      return $rc
    fi
    printf "\e[?25h"
  else
    wait "$pid"
  fi
}

# =================== Step 1: Telegram Config ===================
banner "🤖 Step 1 — Telegram Setup"

# Load .env if exists
if [[ -f .env ]]; then source ./.env; fi

# Get Token
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then
  read -rp "   ${CYAN}💎 Bot Token:${RESET} " TELEGRAM_TOKEN
fi

# Get Chat ID
if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then
  read -rp "   ${CYAN}💎 Chat ID:${RESET}   " TELEGRAM_CHAT_IDS
fi

tg_send(){
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || -z "${TELEGRAM_CHAT_IDS:-}" ]]; then return 0; fi
  
  IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" \
      >>"$LOG_FILE" 2>&1
    ok "Sent to ID: ${_cid}"
  done
}

# =================== Step 2: Project Check ===================
banner "🏗️ Step 2 — GCP Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  printf "   ${RED}✘ No active project.${RESET}\n"
  exit 1
fi
kv "Project ID" "${PROJECT}"

# =================== Step 3: Protocol & Image ===================
banner "🔌 Step 3 — Select Protocol"
echo -e "   ${RED}1.${RESET} VLESS WS"
echo -e "   ${BLUE}2.${RESET} VLESS gRPC"
read -rp "   ${GREEN}Select [1-2]:${RESET} " _opt

# Custom Docker Image Always Used
IMAGE="a0x1/al0x1"

case "${_opt:-1}" in
  2) PROTO="vless-grpc" ;;
  *) PROTO="vless-ws"   ;;
esac
ok "Selected: ${PROTO^^} (Image: $IMAGE)"

# =================== Step 4: Deployment Config ===================
SERVICE_NAME="alphas0x1" # Must be lowercase
REGION="us-central1"
CPU="4"
MEMORY="4Gi"
TIMEOUT="3600"
PORT="8080"

banner "⚙️ Step 4 — Configuration"
kv "Region" "${REGION}"
kv "Service" "${SERVICE_NAME}"
kv "Specs" "${CPU} vCPU / ${MEMORY} RAM"
kv "Instances" "Min: 1 / Max: 2"

# =================== Timezone Setup ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"

# =================== Enable APIs ===================
# Only strictly necessary APIs
run_with_progress "Checking Cloud Run API" \
  gcloud services enable run.googleapis.com --quiet

# =================== Deploy ===================
banner "🚀 Step 5 — Deploying to Cloud Run"
run_with_progress "Deploying Container..." \
  gcloud run deploy "$SERVICE_NAME" \
    --image="$IMAGE" \
    --platform=managed \
    --region="$REGION" \
    --memory="$MEMORY" \
    --cpu="$CPU" \
    --timeout="$TIMEOUT" \
    --allow-unauthenticated \
    --use-http2 \
    --port="$PORT" \
    --min-instances=1 \
    --max-instances=2 \
    --quiet

# =================== Result ===================
URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}

banner "🎉 FINAL RESULT"
kv "Status" "Active"
kv "Domain" "${DOMAIN}"

# =================== Protocol URLs ===================
# UUIDs must match your config.json
VLESS_UUID="0c890000-4733-b20e-067f-fc341bd20000"
VLESS_UUID_GRPC="0c890000-4733-4a0e-9a7f-fc341bd20000"
GRPC_SERVICE_NAME="alpha-grpc"

case "$PROTO" in
  vless-ws)
    # Path removed as requested
    URI="vless://${VLESS_UUID}@vpn.googleapis.com:443?security=tls&encryption=none&host=${DOMAIN}&type=ws#Alpha0x1" 
    ;;
  vless-grpc)
    # ServiceName updated to alpha-grpc
    URI="vless://${VLESS_UUID_GRPC}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${DOMAIN}#Alpha0x1" 
    ;;
esac

# =================== Telegram Notify ===================
banner "📨 Step 6 — Sending Notification"

MSG=$(cat <<EOF
<blockquote>🚀 Alpha0x1 V2RAY SERVICE</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<pre><code>${URI}</code></pre>

<blockquote>✅ စတင်ချိန်: <code>${START_LOCAL}</code></blockquote>
<blockquote>⏳ပြီးဆုံးအချိန်: <code>${END_LOCAL}</code></blockquote>
EOF
)

tg_send "${MSG}"

hr
printf "${GREEN}${BOLD}✅ ALL DONE! Enjoy your Alpha0x1 Server.${RESET}\n"
printf "${C_GREY}📄 Log: ${LOG_FILE}${RESET}\n"
