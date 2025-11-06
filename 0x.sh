#!/usr/bin/env bash
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

# =================== Progress Function ===================
run_with_progress() {
  local label="$1"; shift
  echo "🔄 ${label}..."
  
  local start_time=$(date +%s)
  if "$@" >> "$LOG_FILE" 2>&1; then
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    echo "✅ ${label} completed (${total_time}s)"
    return 0
  else
    local rc=$?
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    echo "❌ ${label} failed after ${total_time}s"
    return $rc
  fi
}

# =================== Telegram Function ===================
json_escape() { 
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

tg_send() {
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then 
    return 0
  fi
  
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" \
      >>"$LOG_FILE" 2>&1
    ok "Telegram sent → ${_cid}"
  done
}

# =================== Time Format Function ===================
fmt_dt() { 
  date -d @"$1" "+%d.%m.%Y %I:%M %p"
}

# =================== Main Script Starts Here ===================
printf "\n${C_CYAN}${BOLD}🚀 KSGCP Cloud Run — 50 Users Trojan WS / gRPC Deploy${RESET}\n"
hr

# =================== Step 1: Telegram Config ===================
banner "🚀 Step 1 — Telegram Setup"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-${TELEGRAM_CHAT_ID:-}}"

if [[ ( -z "${TELEGRAM_TOKEN}" || -z "${TELEGRAM_CHAT_IDS}" ) && -f .env ]]; then
  set -a; source ./.env; set +a
fi

read -rp "🤖 Telegram Bot Token: " _tk || true
[[ -n "${_tk:-}" ]] && TELEGRAM_TOKEN="$_tk"
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then
  warn "Telegram token empty; deploy will continue without messages."
else
  ok "Telegram token captured."
fi

read -rp "👤 Owner/Channel Chat ID(s): " _ids || true
[[ -n "${_ids:-}" ]] && TELEGRAM_CHAT_IDS="${_ids// /}"

CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS:-}" || true

# =================== Step 2: Project ===================
banner "🧭 Step 2 — GCP Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  err "No active project. Run: gcloud config set project <YOUR_PROJECT_ID>"
  exit 1
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
ok "Project Loaded: ${PROJECT}"

# =================== Step 3: Protocol ===================
banner "🧩 Step 3 — Protocol Selection"
echo "  1️⃣ Trojan WS (Recommended - 50 Users)"
echo "  2️⃣ VLESS gRPC (Alternative - 30 Users)"
read -rp "Choose [1-2, default 1]: " _opt || true
case "${_opt:-1}" in
  2) 
    PROTO="vless-grpc" 
    IMAGE="docker.io/n4pro/vlessgrpc:latest"
    MAX_USERS="30"
    ok "Protocol selected: VLESS gRPC (${MAX_USERS} users)"
    ;;
  *) 
    PROTO="trojan-ws" 
    IMAGE="docker.io/n4pro/tr:latest"
    MAX_USERS="50"
    ok "Protocol selected: TROJAN WS (${MAX_USERS} users)"
    ;;
esac

# =================== Step 4: Region ===================
banner "🌍 Step 4 — Region Selection"
REGION="us-central1"
ok "Region: ${REGION} (US Central)"

# =================== Step 5: Resources ===================
banner "💪 Step 5 — Resources"
echo "💡 Auto-set: 8 vCPU / 16GB Memory (50 Users Optimized)"
CPU="8"
MEMORY="16Gi"
CONCURRENCY="100"
ok "CPU/Mem: ${CPU} vCPU / ${MEMORY}"
ok "Max Users: ${MAX_USERS}"
ok "Concurrency: ${CONCURRENCY}"

# =================== Step 6: Service Name ===================
banner "🏷️ Step 6 — Service Name"
SERVICE="ksgcp"
TIMEOUT="${TIMEOUT:-19800}"
PORT="${PORT:-8080}"
ok "Auto-set Service Name: ${SERVICE}"

# =================== Step 7: Timezone Setup ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
DELETE_EPOCH="$(( START_EPOCH + 5*3600 + 300 ))"
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"
DELETE_LOCAL="$(fmt_dt "$DELETE_EPOCH")"
banner "⏰ Step 7 — Deployment Time"
kv "Start:" "${START_LOCAL}"
kv "End:" "${END_LOCAL}"
kv "Auto-Delete:" "${DELETE_LOCAL}"
kv "Max Users:" "${MAX_USERS}"

# =================== Step 8: Enable APIs ===================
banner "🔧 Step 8 — Enable APIs"
run_with_progress "Enabling CloudRun & Build APIs" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# =================== Step 9: Deploy ===================
banner "🚀 Step 9 — Deploying to Cloud Run"
echo "📦 Deploying high-performance service for ${MAX_USERS} users..."
echo "⏳ This may take 5-8 minutes (large container)..."
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
  --max-instances=2 \
  --concurrency="${CONCURRENCY}" \
  --quiet

ok "High-performance deployment completed"

# =================== Step 10: Auto-Delete Setup ===================
banner "🔄 Step 10 — Auto-Delete Setup"
echo "⏰ Setting up auto-delete in 5 hours..."

CLEANUP_SCRIPT="/tmp/cleanup_${SERVICE}.sh"
cat > "$CLEANUP_SCRIPT" << EOF
#!/bin/bash
sleep $((DELETE_EPOCH - $(date +%s)))
gcloud run services delete "$SERVICE" --region="$REGION" --quiet
echo "✅ Auto-deleted service: $SERVICE"
EOF

chmod +x "$CLEANUP_SCRIPT"
nohup bash "$CLEANUP_SCRIPT" > /tmp/cleanup_${SERVICE}.log 2>&1 &
CLEANUP_PID=$!

ok "Auto-delete scheduled for: ${DELETE_LOCAL}"

# =================== Step 11: Result ===================
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"
banner "✅ Result"
ok "High-Performance Service Ready"
kv "URL:" "${C_CYAN}${BOLD}${URL_CANONICAL}${RESET}"
kv "Active Until:" "${END_LOCAL}"
kv "Max Users:" "${MAX_USERS}"
kv "Resources:" "${CPU}vCPU / ${MEMORY}"

# =================== Step 12: Generate Hidden URLs ===================
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

# =================== Step 13: Telegram Notify ===================
banner "📣 Step 13 — Telegram Notification"

MSG=$(cat <<EOF
<blockquote>🚀 KSGCP V2RAY KEY - 50 Users</blockquote>
<blockquote>💪 High Performance: 8vCPU 16GB</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>👥 Max Users: ${MAX_USERS}</blockquote>
<blockquote>📡 Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်!</blockquote>

<pre><code>${URI}</code></pre>

<blockquote>🕒 Active Until: <code>${END_LOCAL}</code></blockquote>
<blockquote>🗑️ Auto-Delete: <code>${DELETE_LOCAL}</code></blockquote>
EOF
)

tg_send "${MSG}"

# =================== Step 14: Keep-Alive Service ===================
{
  echo "🔋 Starting keep-alive service for high-performance instance..."
  while [[ $(date +%s) -lt $END_EPOCH ]]; do
    curl -s --connect-timeout 10 "https://${CANONICAL_HOST}" >/dev/null 2>&1 &
    sleep 30
  done
  echo "🛑 Keep-alive stopped"
} &

printf "\n${C_GREEN}${BOLD}✨ KSGCP ${PROTO^^} Deployed Successfully${RESET}\n"
printf "${C_GREEN}${BOLD}💪 High-Performance: ${CPU}vCPU ${MEMORY} | ${MAX_USERS} Users${RESET}\n"
printf "${C_GREEN}${BOLD}⏰ 5-Hour Guaranteed Service | Auto-Delete Enabled${RESET}\n"
printf "${C_GREY}📄 Log file: ${LOG_FILE}${RESET}\n"
printf "${C_GREY}🔧 Cleanup PID: ${CLEANUP_PID}${RESET}\n\n"
