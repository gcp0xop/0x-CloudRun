#!/usr/bin/env bash
set -euo pipefail

# ===== Ensure interactive reads even when run via curl/process substitution =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & error handler =====
LOG_FILE="/tmp/ksgcp_cloudrun_$(date +%s).log"
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

# =================== Color & UI (Neon/Rainbow Theme) ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'
  BOLD=$'\e[1m'
  # Neon Palette
  C_PINK=$'\e[38;5;201m'
  C_CYAN=$'\e[38;5;51m'
  C_LIME=$'\e[38;5;118m'
  C_ORANGE=$'\e[38;5;214m'
  C_PURPLE=$'\e[38;5;135m'
  C_YELLOW=$'\e[38;5;226m'
  C_WHITE=$'\e[38;5;255m'
  C_RED=$'\e[38;5;196m'
  C_GREY=$'\e[38;5;240m'
else
  RESET= BOLD= C_PINK= C_CYAN= C_LIME= C_ORANGE= C_PURPLE= C_YELLOW= C_WHITE= C_RED= C_GREY=
fi

hr(){ printf "${C_GREY}%s${RESET}\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
banner(){ local title="$1"; printf "\n${C_PINK}${BOLD}✨ %s${RESET}\n${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n" "$title"; }
ok(){ printf " ${C_LIME}✔${RESET} %s\n" "$1"; }
warn(){ printf " ${C_ORANGE}⚠${RESET} %s\n" "$1"; }
err(){ printf " ${C_RED}✘${RESET} %s\n" "$1"; }
kv(){ printf " ${C_CYAN}➤ %-12s${RESET} ${C_WHITE}%s${RESET}\n" "$1" "$2"; }

clear
printf "\n${C_PURPLE}${BOLD}🚀 KSGCP CLOUD RUN DEPLOYER${RESET} ${C_ORANGE}(VLESS gRPC Edition)${RESET}\n"
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
      printf "\r ${C_YELLOW}${spin:$i:1}${RESET} %s..." "$label"
      sleep 0.1
    done
    wait "$pid"; local rc=$?
    printf "\r\e[K" # Clear line
    if (( rc==0 )); then
      printf " ${C_LIME}✅${RESET} %s\n" "$label"
    else
      printf " ${C_RED}❌${RESET} %s failed (see %s)\n" "$label" "$LOG_FILE"
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

read -rp " ${C_PURPLE}💎 Bot Token:${RESET} " _tk || true
[[ -n "${_tk:-}" ]] && TELEGRAM_TOKEN="$_tk"

if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then
  warn "Token empty! No notifications will be sent."
else
  ok "Token saved."
fi

read -rp " ${C_PURPLE}💎 Chat ID:${RESET} " _ids || true
[[ -n "${_ids:-}" ]] && TELEGRAM_CHAT_IDS="${_ids// /}"

CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS:-}" || true

tg_send(){
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then return 0; fi
  
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" >>"$LOG_FILE" 2>&1
    ok "Sent to ID: ${_cid}"
  done
}

# =================== Step 2: Project ===================
banner "🏗️ Step 2 — GCP Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  err "No active project. Run: gcloud config set project ID"
  exit 1
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
kv "Project ID" "${PROJECT}"

# =================== Step 3: Configuration ===================
IMAGE="docker.io/n4pro/vlessgrpc:latest"
REGION="us-central1"
CPU="2"
MEMORY="4Gi"
SERVICE="alpha0x1"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"

banner "⚙️ Step 3 — Configuration"
kv "Region" "${REGION}"
kv "Service" "${SERVICE}"
kv "Protocol" "VLESS gRPC Only"
kv "Specs" "${CPU} CPU / ${MEMORY} RAM"

# =================== Timezone Setup (5 Hours Calculation) ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 18000 ))" # 18000 seconds = 5 hours

fmt_dt(){ date -d @"$1" "+%I:%M %p"; }
END_LOCAL="$(fmt_dt "$END_EPOCH")"

banner "🕒 Step 4 — Time Limit"
kv "End Time" "${END_LOCAL}"

# =================== Enable APIs ===================
banner "🔧 Step 5 — Setup APIs"
run_with_progress "Enabling CloudRun API" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# =================== Deploy ===================
banner "🚀 Step 6 — Deploying"
# Using --use-http2 is CRITICAL for gRPC
run_with_progress "Pushing ${SERVICE} to Cloud Run (HTTP/2 enabled)" \
  gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --timeout="$TIMEOUT" \
  --allow-unauthenticated \
  --port="$PORT" \
  --min-instances=1 \
  --use-http2 \
  --quiet

# =================== Result ===================
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"

banner "🎉 FINAL RESULT"
kv "Status" "Active"
kv "Domain" "${URL_CANONICAL}"

# =================== Protocol URLs ===================
VLESS_UUID_GRPC="0c890000-4733-4a0e-9a7f-fc341bd20000"

# VLESS gRPC URI
URI_VLESS="vless://${VLESS_UUID_GRPC}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=n4-grpc&sni=${CANONICAL_HOST}#Alpha0x1-VLESS"

echo ""
echo " ${C_LIME}🔹 KEY: VLESS gRPC${RESET}"
echo " ${C_WHITE}${URI_VLESS}${RESET}"
echo ""

# =================== Telegram Notify ===================
banner "📨 Step 7 — Sending Notification"

MSG=$(cat <<EOF
<blockquote>🚀 ALPHA0x1 VLESS SERVICE</blockquote>
<blockquote>💎 Premium Server Active</blockquote>
<blockquote>📡 Mytel 4G Supported</blockquote>

<b>1️⃣ VLESS gRPC:</b>
<pre><code>${URI_VLESS}</code></pre>

<blockquote>❌ ပြီးဆုံးချိန်: <code>${END_LOCAL}</code></blockquote>
EOF
)

tg_send "${MSG}"

printf "\n${C_LIME}${BOLD}✅ ALL DONE! Enjoy your Alpha0x1 Server.${RESET}\n"
printf "${C_GREY}📄 Log: ${LOG_FILE}${RESET}\n"
