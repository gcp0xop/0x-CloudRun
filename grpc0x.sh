#!/usr/bin/env bash
set -euo pipefail

# ===== Ensure interactive reads even when run via curl/process substitution =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & error handler =====
LOG_FILE="/tmp/alpha0x1_deploy_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO: ${BASH_COMMAND}" | tee -a "$LOG_FILE" >&2
  echo "—— LOG (last 80 lines) ——" >&2
  tail -n 80 "$LOG_FILE" >&2 || true
  echo "📄 Log File: $LOG_FILE" >&2
  exit $rc
}
trap on_err ERR

# =================== Color & UI (Gold/Luxury Theme) ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'
  BOLD=$'\e[1m'
  
  # Gold & Luxury Palette
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
  local title="$1"
  printf "\n${C_GOLD}${BOLD}✨ %s${RESET}\n${C_ORANGE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n" "$title"
}
ok(){   printf "   ${C_LIME}✔${RESET} %s\n" "$1"; }
warn(){ printf "   ${C_ORANGE}⚠${RESET} %s\n" "$1"; }
err(){  printf "   ${C_RED}✘${RESET} %s\n" "$1"; }
kv(){   printf "   ${C_YELLOW}➤ %-12s${RESET} ${C_WHITE}%s${RESET}\n" "$1" "$2"; }

clear
printf "\n${C_GOLD}${BOLD}🚀 Alpha0x1 CLOUD RUN DEPLOYER${RESET} ${C_ORANGE}(Custom Docker Edition)${RESET}\n"
hr

# =================== Simple spinner ===================
run_with_progress() {
  local label="$1"; shift
  ( "$@" ) >>"$LOG_FILE" 2>&1 &
  local pid=$!
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  if [[ -t 1 ]]; then
    printf "\e[?25l" # Hide cursor
    while kill -0 "$pid" 2>/dev/null; do
      i=$(( (i+1) %10 ))
      printf "\r   ${C_GOLD}${spin:$i:1}${RESET} %s..." "$label"
      sleep 0.1
    done
    wait "$pid"; local rc=$?
    printf "\r\e[K" # Clear line
    if (( rc==0 )); then
      printf "   ${C_LIME}✅${RESET} %s\n" "$label"
    else
      printf "   ${C_RED}❌${RESET} %s failed (see %s)\n" "$label" "$LOG_FILE"
      return $rc
    fi
    printf "\e[?25h" # Show cursor
  else
    wait "$pid"
  fi
}

# =================== Step 1: Telegram Config ===================
banner "🤖 Step 1 — Telegram Setup"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-${TELEGRAM_CHAT_ID:-}}"

if [[ ( -z "${TELEGRAM_TOKEN}" || -z "${TELEGRAM_CHAT_IDS}" ) && -f .env ]]; then
  set -a; source ./.env; set +a
fi

if [[ -z "${TELEGRAM_TOKEN}" ]]; then
  read -rp "   ${C_GOLD}💎 Bot Token:${RESET} " _tk || true
  [[ -n "${_tk:-}" ]] && TELEGRAM_TOKEN="$_tk"
else
  ok "Token found."
fi

if [[ -z "${TELEGRAM_CHAT_IDS}" ]]; then
  read -rp "   ${C_GOLD}💎 Chat ID:${RESET}   " _ids || true
  [[ -n "${_ids:-}" ]] && TELEGRAM_CHAT_IDS="${_ids// /}"
else
  ok "Chat ID found."
fi

CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS:-}" || true

tg_send(){
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then return 0; fi
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" \
      >>"$LOG_FILE" 2>&1
    ok "Sent to ID: ${_cid}"
  done
}

# =================== Step 2: Project ===================
banner "🏗️ Step 2 — GCP Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"

# Fix for unset project
if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  echo "   ${C_ORANGE}⚠️ Project ID not detected automatically.${RESET}"
  read -rp "   👉 Please Enter Project ID: " PROJECT
fi

if [[ -z "$PROJECT" ]]; then
  err "No active project. Run: gcloud config set project ID"
  exit 1
fi

gcloud config set project "$PROJECT" --quiet >/dev/null 2>&1
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
kv "Project ID" "${PROJECT}"

# =================== Step 3: Configuration ===================
banner "⚙️ Step 3 — Configuration"

# CUSTOM SETTINGS FOR YOUR DOCKER
IMAGE="docker.io/a0x1/al0x1:latest"
SERVICE="alpha0x1"
SERVICE_NAME="alphas0x1"  # Internal service name for gRPC
UUID="$(cat /proc/sys/kernel/random/uuid)" # Random UUID
REGION="us-central1"
CPU="2"
MEMORY="2Gi"
PORT="8080"

kv "Region" "${REGION}"
kv "Image" "${IMAGE}"
kv "Spec" "${CPU} CPU / ${MEMORY} RAM"
kv "UUID" "${UUID}"

# =================== Timezone Setup ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))" # 5 hours later
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"

banner "🕒 Step 4 — Deployment Time"
kv "Start:" "${START_LOCAL}"
kv "End:"   "${END_LOCAL}"

# =================== Enable APIs ===================
banner "🔧 Step 5 — Setup APIs"
run_with_progress "Enabling CloudRun API" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# =================== Deploy ===================
banner "🚀 Step 6 — Deploying"
run_with_progress "Pushing ${SERVICE} to Cloud Run" \
  gcloud run deploy "$SERVICE" \
    --image="$IMAGE" \
    --platform=managed \
    --region="$REGION" \
    --memory="$MEMORY" \
    --cpu="$CPU" \
    --set-env-vars UUID="$UUID" \
    --set-env-vars SERVICE_NAME="$SERVICE_NAME" \
    --use-http2 \
    --allow-unauthenticated \
    --port="$PORT" \
    --concurrency=200 \
    --min-instances=1 \
    --max-instances=4 \
    --quiet

# =================== Result ===================
URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)' 2>/dev/null || true)"

if [[ -z "$URL" ]]; then
  echo "   ${C_RED}❌ Deployment Failed! Check logs.${RESET}"
  tail -n 10 "$LOG_FILE"
  exit 1
fi

HOST="${URL#https://}"
# Generating vpn.googleapis.com Link
URI="vless://${UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${SERVICE_NAME}&sni=${HOST}#Alpha0x1"

banner "🎉 FINAL RESULT"
kv "Status" "Active"
kv "Host" "${HOST}"
kv "Address" "vpn.googleapis.com"

# =================== Telegram Notify ===================
banner "📨 Step 7 — Sending Notification"

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

printf "\n${C_LIME}${BOLD}✅ ALL DONE! Enjoy your Alpha0x1 Server.${RESET}\n"
printf "${C_GREY}📄 Log: ${LOG_FILE}${RESET}\n"
