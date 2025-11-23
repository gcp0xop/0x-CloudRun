#!/usr/bin/env bash
set -euo pipefail

# ===== Logging & Error Handler =====
LOG_FILE="/tmp/alpha0x1_custom_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  echo ""
  echo "❌ ERROR: Command failed at line $LINENO. See log: $LOG_FILE" >&2
  exit 1
}
trap on_err ERR

# =================== Color & UI (Gold/Luxury Theme) ===================
if [[ -t 1 ]]; then
  RESET=$'\e[0m'
  BOLD=$'\e[1m'
  C_GOLD=$'\e[38;5;220m'
  C_YELLOW=$'\e[38;5;226m'
  C_ORANGE=$'\e[38;5;214m'
  C_LIME=$'\e[38;5;118m'
  C_RED=$'\e[38;5;196m'
  C_GREY=$'\e[38;5;240m'
  C_WHITE=$'\e[38;5;255m'
else
  RESET= BOLD= C_GOLD= C_YELLOW= C_ORANGE= C_LIME= C_RED= C_GREY= C_WHITE=
fi

hr(){ printf "${C_GREY}%s${RESET}\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
banner(){
  printf "\n${C_GOLD}${BOLD}✨ %s${RESET}\n${C_ORANGE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n" "$1"
}
ok(){   printf "   ${C_LIME}✔${RESET} %s\n" "$1"; }
kv(){   printf "   ${C_YELLOW}➤ %-12s${RESET} ${C_WHITE}%s${RESET}\n" "$1" "$2"; }

clear
printf "\n${C_GOLD}${BOLD}🚀 Alpha0x1 CLOUD RUN DEPLOYER${RESET} ${C_ORANGE}(Custom Docker Edition)${RESET}\n"
hr

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

# =================== Step 2: Project Fix ===================
banner "🏗️ Step 2 — GCP Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"

# Project ID မရှိရင် မေးမယ်
if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  echo "   ${C_ORANGE}⚠️ Project ID not detected automatically.${RESET}"
  read -rp "   👉 Please Enter Project ID: " PROJECT
fi

if [[ -z "$PROJECT" ]]; then
  echo "   ${C_RED}❌ Error: Project ID is required!${RESET}"
  exit 1
fi

gcloud config set project "$PROJECT" --quiet >/dev/null 2>&1
kv "Project ID" "${PROJECT}"

# =================== Step 3: Configuration ===================
banner "⚙️ Step 3 — Configuration"

# CUSTOM DOCKER IMAGE
IMAGE="docker.io/a0x1/al0x1:latest"

# REGION (US Default)
REGION="us-central1"

# SPECS (High Performance)
CPU="4"
MEMORY="4Gi"

# SERVICE INFO
SERVICE="alpha0x1"
SERVICE_NAME="grpc"  # For gRPC
UUID="$(cat /proc/sys/kernel/random/uuid)" # Random UUID

kv "Image" "${IMAGE}"
kv "Region" "${REGION}"
kv "Spec" "${CPU} CPU / ${MEMORY} RAM"
kv "UUID" "${UUID}"

# =================== Enable APIs ===================
banner "🔧 Step 4 — Enabling APIs"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet >/dev/null 2>&1
ok "APIs Enabled"

# =================== Deploy ===================
banner "🚀 Step 5 — Deploying (Please Wait...)"

gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --set-env-vars UUID="$UUID" \
  --set-env-vars SERVICE_NAME="$SERVICE_NAME" \
  --use-http2 \
  --timeout=3600 \
  --allow-unauthenticated \
  --port=8080 \
  --min-instances=1 \
  --max-instances=2 \
  --concurrency=500 \
  --quiet >>"$LOG_FILE" 2>&1

# =================== Result ===================
URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)' 2>/dev/null || true)"

if [[ -z "$URL" ]]; then
  echo "   ${C_RED}❌ Deployment Failed! Check logs.${RESET}"
  tail -n 10 "$LOG_FILE"
  exit 1
fi

HOST="${URL#https://}"
URI="vless://${UUID}@${HOST}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${SERVICE_NAME}&sni=${HOST}#Alpha0x1"

# Timezone Setup
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"

banner "🎉 FINAL RESULT"
kv "Status" "Active"
kv "Domain" "${HOST}"
echo ""
echo "   ${C_GOLD}👇 COPY THIS LINK 👇${RESET}"
echo "${C_WHITE}${URI}${RESET}"
echo ""

# =================== Telegram Notify ===================
banner "📨 Step 6 — Sending Notification"

MSG=$(cat <<EOF
<blockquote>🚀 Alpha0x1 V2RAY SERVICE</blockquote>
<blockquote>💎 ⏰ 5-Hour Free Service</blockquote>
<blockquote>📡 Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<pre><code>${URI}</code></pre>

<blockquote>✅ စတင်ချိန်: <code>${START_LOCAL}</code></blockquote>
<blockquote>⏳ ပြီးဆုံးအချိန်: <code>${END_LOCAL}</code></blockquote>
EOF
)

tg_send "${MSG}"
ok "Notification Sent"

printf "\n${C_LIME}${BOLD}✅ ALL DONE! Enjoy your Custom Server.${RESET}\n"
printf "${C_GREY}📄 Log: ${LOG_FILE}${RESET}\n"
