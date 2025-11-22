#!/usr/bin/env bash
set -euo pipefail

# ===== Logging & Error Handler =====
LOG_FILE="/tmp/alpha0x1_grpc_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  echo ""
  echo "❌ ERROR: Command failed at line $LINENO. See log: $LOG_FILE" >&2
  exit 1
}
trap on_err ERR

# =================== Gold Theme UI ===================
if [[ -t 1 ]]; then
  RESET=$'\e[0m'
  BOLD=$'\e[1m'
  C_GOLD=$'\e[38;5;220m'      # Gold
  C_YELLOW=$'\e[38;5;226m'    # Bright Yellow
  C_ORANGE=$'\e[38;5;214m'    # Warm
  C_LIME=$'\e[38;5;118m'      # Success
  C_RED=$'\e[38;5;196m'       # Error
  C_GREY=$'\e[38;5;240m'
else
  RESET= BOLD= C_GOLD= C_YELLOW= C_ORANGE= C_LIME= C_RED= C_GREY=
fi

banner(){
  printf "\n${C_GOLD}${BOLD}✨ %s${RESET}\n${C_ORANGE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n" "$1"
}
ok(){   printf "   ${C_LIME}✔${RESET} %s\n" "$1"; }
kv(){   printf "   ${C_YELLOW}➤ %-12s${RESET} ${RESET}%s${RESET}\n" "$1" "$2"; }

clear
printf "\n${C_GOLD}${BOLD}🚀 Alpha0x1 gRPC DEPLOYER${RESET} ${C_ORANGE}(Custom Docker Edition)${RESET}\n"
echo "   ${C_GREY}Docker Image: docker.io/a0x1/al0x1:latest${RESET}"
printf "${C_GREY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

# =================== Step 1: Telegram Setup ===================
banner "🤖 Step 1 — Telegram Setup"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-}"

if [[ -z "${TELEGRAM_TOKEN}" ]]; then
  read -rp "   ${C_GOLD}💎 Bot Token:${RESET} " _tk || true
  [[ -n "${_tk}" ]] && TELEGRAM_TOKEN="$_tk"
fi
if [[ -z "${TELEGRAM_CHAT_IDS}" ]]; then
  read -rp "   ${C_GOLD}💎 Chat ID:${RESET}   " _ids || true
  [[ -n "${_ids}" ]] && TELEGRAM_CHAT_IDS="${_ids// /}"
fi

tg_send(){
  local text="$1"
  [[ -z "${TELEGRAM_TOKEN}" || -z "${TELEGRAM_CHAT_IDS}" ]] && return 0
  IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" --data-urlencode "text=${text}" -d "parse_mode=HTML" >>"$LOG_FILE" 2>&1 || true
  done
}

# =================== Step 2: Region & Project ===================
banner "🌍 Step 2 — Configuration"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  echo "   ${C_RED}❌ No Active Project found!${RESET}"
  exit 1
fi
kv "Project" "${PROJECT}"

echo ""
echo "   ${C_YELLOW}1.${RESET} US Central (Iowa) [Default]"
echo "   ${C_YELLOW}2.${RESET} Asia Northeast (Tokyo) [Faster]"
read -rp "   ${C_ORANGE}Select Region [1-2]:${RESET} " _reg
case "${_reg:-1}" in
  2) REGION="asia-northeast1" ;;
  *) REGION="us-central1"     ;;
esac
ok "Region Set: $REGION"

# =================== Step 3: Generate Keys ===================
banner "🔐 Step 3 — Generating Keys"
# Random UUID generation
UUID="$(cat /proc/sys/kernel/random/uuid)"
SERVICE_NAME="grpc"  # Fixed for simplicity, or can be random
kv "UUID" "$UUID"
kv "Type" "VLESS gRPC"

# =================== Step 4: High Performance Deploy ===================
banner "🚀 Step 4 — Deploying High Spec Server"
SERVICE="alpha0x1-us"  # နာမည်ပြောင်းထားတယ်
REGION="us-central1"    # US Only

echo "   ${C_GREY}Spec: 4 CPU / 4GB RAM (Target: 200 Users)${RESET}"

gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --allow-unauthenticated \
  --set-env-vars UUID="$UUID" \
  --set-env-vars SERVICE_NAME="$SERVICE_NAME" \
  --use-http2 \
  --port=8080 \
  --timeout=3600 \
  --memory=4Gi \        # <--- RAM 4GB
  --cpu=4 \             # <--- CPU 4 Core
  --concurrency=500 \   # <--- လူ ၂၀၀ အေးဆေးဆံ့အောင် ၅၀၀ ထားပေးတယ်
  --min-instances=1 \   # <--- အနည်းဆုံး ၁ လုံး အမြဲ run မယ်
  --max-instances=10 \  # <--- လိုအပ်ရင် ၁၀ လုံးထိ တိုးမယ်
  --quiet >>"$LOG_FILE" 2>&1

# Check Result
URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)' 2>/dev/null || true)"

if [[ -z "$URL" ]]; then
  echo "   ${C_RED}❌ Deployment Failed! Check logs.${RESET}"
  tail -n 10 "$LOG_FILE"
  exit 1
fi

# Clean URL (remove https://)
HOST="${URL#https://}"

# =================== Result ===================
banner "🎉 FINAL RESULT"
# VLESS gRPC Link Format
URI="vless://${UUID}@${HOST}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${SERVICE_NAME}&sni=${HOST}#Alpha0x1_gRPC"

kv "Host" "${HOST}"
kv "Status" "Active"
echo ""
echo "   ${C_GOLD}👇 COPY THIS LINK 👇${RESET}"
echo "${C_WHITE}${URI}${RESET}"
echo ""

# =================== Notification & Save ===================
# Save to File
echo "Alpha0x1 gRPC ($(date))" >> alpha_config.txt
echo "Link: ${URI}" >> alpha_config.txt
echo "--------------------------------" >> alpha_config.txt
ok "Saved to alpha_config.txt"

# Send Telegram
MSG=$(cat <<EOF
<blockquote>🚀 Alpha0x1 gRPC Server</blockquote>
<blockquote>⏰ 5-Hour Free Service: a0x1</blockquote>
<blockquote>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်: ${REGION}</blockquote>
<pre><code>${URI}</code></pre>
EOF
)
tg_send "${MSG}"
ok "Notification Sent"

printf "\n${C_LIME}${BOLD}✅ Enjoy your private gRPC server!${RESET}\n"
