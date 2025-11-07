#!/bin/bash
set -euo pipefail

# ===== Ensure interactive reads even when run via curl/process substitution =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & error handler =====
LOG_FILE="/tmp/ksgcp_cloudrun_$(date +%s).log"
touch "$LOG_FILE"

# ===== Error Handler =====
on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO: ${BASH_COMMAND}" | tee -a "$LOG_FILE" >&2
  # This will now show the REAL error from the log file
  echo "—— LOG (last 80 lines) ——" >&2
  tail -n 80 "$LOG_FILE" >&2 || true
  echo "📄 Log File: $LOG_FILE" >&2
  exit $rc
}

# Set trap AFTER function definition
trap on_err ERR

# =================== Color & UI Functions ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
  C_CYAN=$'\e[38;5;44m'; C_BLUE=$'\e[38;5;33m'
  C_GREEN=$'\e[38;5;46m'; C_YEL=$'\e[38;5;226m'
  C_ORG=$'\e[38;5;214m'; C_PINK=$'\e[38;5;205m'
  C_GREY=$'\e[38;5;245m'; C_RED=$'\e[38;5;196m'
else
  RESET=''; BOLD=''; DIM=''; C_CYAN=''; C_BLUE=''; C_GREEN=''; C_YEL=''; C_ORG=''; C_PINK=''; C_GREY=''; C_RED=''
fi

hr() { 
  printf "${C_GREY}%s${RESET}\n" "──────────────────────────────────────────────"
}

banner() {
  local title="$1"
  printf "\n${C_BLUE}${BOLD}╔══════════════════════════════════════════════════╗${RESET}\n"
  printf "${C_BLUE}${BOLD}║${RESET}  %s${RESET}\n" "$(printf "%-46s" "$title")"
  printf "${C_BLUE}${BOLD}╚══════════════════════════════════════════════════╝${RESET}\n"
}

ok() { 
  printf "${C_GREEN}✔${RESET} %s\n" "$1"
}

warn() { 
  printf "${C_ORG}⚠${RESET} %s\n" "$1"
}

err() { 
  printf "${C_RED}✘${RESET} %s\n" "$1"
}

kv() { 
  printf "   ${C_GREY}%s${RESET}  %s\n" "$1" "$2"
}

# =================== Hidden Configuration =====
decode_cfg() { 
  case "$1" in
    "trojan_pass") echo "Trojan-2025" ;;
    "vless_uuid_grpc") echo "0c890000-4733-4a0e-9a7f-fc341bd20000" ;;
    "ws_path") echo "/N4" ;;
    "grpc_service") echo "n4-grpc" ;;
    "tls_sni") echo "vpn.googleapis.com" ;;
    "port") echo "443" ;;
    "network") echo "ws" ;;
    "security") echo "tls" ;;
    *) echo "" ;;
  esac
}

# =================== Telegram Function ===================
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g' -e 's/\t/\\t/g' -e 's/\r//g'
}

tg_send() {
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then 
    return 0
  fi
  
  local escaped_text
  escaped_text=$(json_escape "$text")

  for _cid in "${CHAT_ID_ARR[@]}"; do
    local json_payload
    json_payload=$(printf '{"chat_id": "%s", "text": "%s", "parse_mode": "HTML"}' \
                    "$_cid" \
                    "$escaped_text")
    
    # We will not hide the error message in the log file anymore
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -H "Content-Type: application/json" \
      -d "${json_payload}"
      
    ok "Telegram sent → ${_cid}"
  done
}

# =================== Time Format Function ===================
fmt_dt() { 
  date -d @"$1" "+%d.%m.%Y %I:%M %p"
}

# =================== Main Script Starts Here ===================
printf "\n${C_CYAN}${BOLD}🚀 KSGCP Cloud Run — Simplified Deploy${RESET}\n"
hr

# =================== Step 1: Telegram Config ===================
banner "🚀 Step 1 — Telegram Setup"
read -rp "🤖 Telegram Bot Token: " TELEGRAM_TOKEN || true
read -rp "👤 Owner/Channel Chat ID(s): " TELEGRAM_CHAT_IDS || true
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS// /}"
CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS:-}" || true

# =================== Step 2: Project ===================
banner "🧭 Step 2 — GCP Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  err "No active project. Run: gcloud config set project <YOUR_PROJECT_ID>"
  exit 1
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ok "Project Loaded: ${PROJECT}"

# =================== Step 3: Protocol ===================
banner "🧩 Step 3 — Protocol Selection"
echo "  1️⃣ Trojan WS (Recommended)"
echo "  2️⃣ VLESS gRPC (Alternative)"
read -rp "Choose [1-2, default 1]: " _opt || true
case "${_opt:-1}" in
  2) 
    PROTO="vless-grpc" 
    IMAGE="docker.io/n4pro/vlessgrpc:latest"
    ok "Protocol selected: VLESS gRPC"
    ;;
  *) 
    PROTO="trojan-ws" 
    IMAGE="docker.io/n4pro/tr:latest"
    ok "Protocol selected: TROJAN WS"
    ;;
esac

# =================== Step 4: Region ===================
banner "🌍 Step 4 — Region Selection"
REGION="us-central1"
ok "Region: ${REGION} (US Central)"

# =================== Step 5: Resources ===================
banner "💪 Step 5 — Resources"
echo "💡 Auto-set: 2 vCPU / 2Gi Memory (User Requested)"
CPU="2"
MEMORY="2Gi"
CONCURRENCY="100"
ok "CPU/Mem: ${CPU} vCPU / ${MEMORY}"
ok "Concurrency: ${CONCURRENCY}"

# =================== Step 6: Service Name ===================
banner "🏷️ Step 6 — Service Name"
SERVICE="ksgcp"
TIMEOUT="3600"
PORT="${PORT:-8080}"
ok "Auto-set Service Name: ${SERVICE}"
ok "Request Timeout: ${TIMEOUT}s"

# =================== Step 7: Timezone Setup ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 18600 ))" # 5 hours 10 minutes
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"
banner "⏰ Step 7 — Deployment Time"
kv "Start:" "${START_LOCAL}"
kv "End:" "${END_LOCAL} (Lab Time)"

# =================== STEP 8: (REMOVED) Enable APIs ===================
# This step was causing the 'Permission Denied' error.
# We assume the Lab has enabled these APIs already.
ok "Skipping API Enable (Assuming Lab default)"

# =================== Step 8: Deploy (Was Step 9) ===================
banner "🚀 Step 8 — Deploying to Cloud Run"
echo "⏳ This may take 3-5 minutes..."
echo "   (Error messages will now appear directly below if they occur)"

# This command will print its REAL error message to the terminal if it fails
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
  --max-instances=10 \
  --concurrency="${CONCURRENCY}" \
  --quiet

ok "Deployment completed"

# =================== STEP 9: (REMOVED) Auto-Delete ===================
# This step required the terminal to stay open, which is unreliable.
# The Lab will delete the service when it expires.
ok "Skipping Auto-Delete (Lab will auto-clean)"

# =================== Step 9: Result (Was Step 11) ===================
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"
banner "✅ Result"
ok "Service Ready"
kv "URL:" "${C_CYAN}${BOLD}${URL_CANONICAL}${RESET}"
kv "Active Until:" "${END_LOCAL}"
kv "Resources:" "${CPU}vCPU / ${MEMORY}"

# =================== Step 10: Generate Hidden URLs (Was Step 12) ===================
TROJAN_PASS=$(decode_cfg "trojan_pass")
VLESS_UUID_GRPC=$(decode_cfg "vless_uuid_grpc")
WS_PATH=$(decode_cfg "ws_path")
GRPC_SERVICE=$(decode_cfg "grpc_service")
TLS_SNI=$(decode_cfg "tls_sni")
CONN_PORT=$(decode_cfg "port")
NETWORK_TYPE=$(decode_cfg "network")
SECURITY_TYPE=$(decode_cfg "security")

WS_PATH_ENCODED=$(echo "$WS_PATH" | sed 's|/|%2F|g')

case "$PROTO" in
  trojan-ws)  
    URI="trojan://${TROJAN_PASS}@${TLS_SNI}:${CONN_PORT}?path=${WS_PATH_ENCODED}&security=${SECURITY_TYPE}&host=${CANONICAL_HOST}&type=${NETWORK_TYPE}#Trojan-WS" 
    ;;
  vless-grpc) 
    URI="vless://${VLESS_UUID_GRPC}@${TLS_SNI}:${CONN_PORT}?mode=gun&security=${SECURITY_TYPE}&encryption=none&type=grpc&serviceName=${GRPC_SERVICE}&sni=${CANONICAL_HOST}#VLESS-gRPC" 
    ;;
esac

# =================== Step 11: Telegram Notify (Was Step 13) ===================
banner "📣 Step 11 — Telegram Notification"

MSG=$(cat <<EOF
<blockquote>🚀 KSGCP V2RAY KEY</blockquote>
<blockquote>⏰ 5-Hour Free Service (Lab Time)</blockquote>
<blockquote>📡 Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်!</blockquote>

<pre><code>${URI}</code></pre>

<blockquote>⏳ End: @ <code>${END_LOCAL}</code></blockquote>
EOF
)

tg_send "${MSG}"

# =================== STEP 12: (REMOVED) Keep-Alive Service ===================
ok "✅ Service is set to --min-instances=1 (will not sleep)"


printf "\n${C_GREEN}${BOLD}✨ KSGCP ${PROTO^^} Deployed Successfully${RESET}\n"
printf "${C_GREEN}${BOLD}💪 Resources: ${CPU}vCPU ${MEMORY}${RESET}\n"
printf "${C_GREEN}${BOLD}✅ You can SAFELY CLOSE this terminal now.${RESET}\n\n"
