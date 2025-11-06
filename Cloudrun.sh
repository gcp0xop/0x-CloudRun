#!/usr/bin/env bash
set -euo pipefail

# ===== Hidden Configuration =====
decode_cfg() { 
  case "$1" in
    "trojan_pass") echo "Trojan-2025" ;;
    "vless_uuid") echo "0c890000-4733-b20e-067f-fc341bd20000" ;;
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

# ===== Ensure interactive reads =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & error handler =====
LOG_FILE="/tmp/0x_cloudrun_$(date +%s).log"
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

# =================== Color & UI ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
  C_CYAN=$'\e[38;5;44m'; C_BLUE=$'\e[38;5;33m'
  C_GREEN=$'\e[38;5;46m'; C_YEL=$'\e[38;5;226m'
  C_ORG=$'\e[38;5;214m'; C_PINK=$'\e[38;5;205m'
  C_GREY=$'\e[38;5;245m'; C_RED=$'\e[38;5;196m'
else
  RESET= BOLD= DIM= C_CYAN= C_BLUE= C_GREEN= C_YEL= C_ORG= C_PINK= C_GREY= C_RED=
fi

hr(){ printf "${C_GREY}%s${RESET}\n" "──────────────────────────────────────────────"; }
banner(){
  local title="$1"
  printf "\n${C_BLUE}${BOLD}╔══════════════════════════════════════════════════╗${RESET}\n"
  printf   "${C_BLUE}${BOLD}║${RESET}  %s${RESET}\n" "$(printf "%-46s" "$title")"
  printf   "${C_BLUE}${BOLD}╚══════════════════════════════════════════════════╝${RESET}\n"
}
ok(){   printf "${C_GREEN}✔${RESET} %s\n" "$1"; }
warn(){ printf "${C_ORG}⚠${RESET} %s\n" "$1"; }
err(){  printf "${C_RED}✘${RESET} %s\n" "$1"; }
kv(){   printf "   ${C_GREY}%s${RESET}  %s\n" "$1" "$2"; }

printf "\n${C_CYAN}${BOLD}🔥 freegcp0x Cloud Run — Premium Deploy${RESET} ${C_GREY}(Trojan WS / VLESS WS / VLESS gRPC)${RESET}\n"
hr

# =================== SIMPLE Progress (No Hanging) ===================
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
    echo "❌ ${label} failed after ${total_time}s (see ${LOG_FILE})"
    return $rc
  fi
}

# =================== Step 1: Telegram Config ===================
banner "🔰 Step 1 — freegcp0x Telegram Setup"
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

json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

tg_send(){
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then return 0; fi
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" \
      >>"$LOG_FILE" 2>&1
    ok "Telegram sent → ${_cid}"
  done
}

# =================== Step 2: Project ===================
banner "🎯 Step 2 — freegcp0x Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  err "No active project. Run: gcloud config set project <YOUR_PROJECT_ID>"
  exit 1
fi
ok "Project Loaded: ${PROJECT}"

# =================== Step 3: Protocol ===================
banner "⚡ Step 3 — freegcp0x Protocol"
echo "  1️⃣ Trojan WS"
echo "  2️⃣ VLESS WS"
echo "  3️⃣ VLESS gRPC"
read -rp "Choose [1-3, default 1]: " _opt || true
case "${_opt:-1}" in
  2) PROTO="vless-ws"   ; IMAGE="docker.io/n4pro/vl:latest"        ;;
  3) PROTO="vless-grpc" ; IMAGE="docker.io/n4pro/vlessgrpc:latest" ;;
  *) PROTO="trojan-ws"  ; IMAGE="docker.io/n4pro/tr:latest"        ;;
esac
ok "Protocol selected: ${PROTO^^}"
echo "[Docker Hidden] ${IMAGE}" >>"$LOG_FILE"

# =================== Step 4: Region ===================
banner "🌏 Step 4 — freegcp0x Region"
REGION="us-east4"
ok "Auto-selected Region: ${REGION}"

# =================== Step 5: Resources ===================
banner "💪 Step 5 — freegcp0x Resources"
echo "💡 Auto-set: 2 vCPU / 8GB Memory (Optimized Tier)"
CPU="2"
MEMORY="8Gi"
ok "CPU/Mem: ${CPU} vCPU / ${MEMORY}"

# =================== Step 6: Service Name ===================
banner "🏷️ Step 6 — freegcp0x Service Name"
SERVICE="ks-gcp" # ⭐️ FIXED: Changed _ to - and made lowercase
# ⭐️ FIXED: Timeout set to 3600 (1 hour), the maximum allowed by Cloud Run.
TIMEOUT="3600" 
PORT="${PORT:-8080}"
ok "Service Name: ${SERVICE}"
ok "Request Timeout: ${TIMEOUT}s (Cloud Run Max)"

# =================== Timezone Setup ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
DELETE_EPOCH="$(( START_EPOCH + 5*3600 + 300 ))" # ⭐️ ADDED: 5.5 hour deletion time
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"
DELETE_LOCAL="$(fmt_dt "$DELETE_EPOCH")" # ⭐️ ADDED
banner "⏰ Step 7 — freegcp0x Deployment Time"
kv "Start:" "${START_LOCAL}"
kv "End:"   "${END_LOCAL} (2 Hours)"
kv "Auto-Delete:" "${DELETE_LOCAL}" # ⭐️ ADDED

# =================== Enable APIs ===================
banner "🔧 Step 8 — freegcp0x Enable APIs"
run_with_progress "Enabling CloudRun & Build APIs" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# =================== Deploy ===================
banner "🚀 Step 9 — freegcp0x Deploying to Cloud Run"
echo "📦 This may take 3-5 minutes for container deployment..."

# Remove --quiet flag to see real progress
echo "🔄 Deploying ${SERVICE}..."
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
  --concurrency=80 \
  --quiet
# --quiet flag re-added for clean output, logs go to $LOG_FILE

ok "Deployment completed successfully"

# =================== Result ===================
banner "🎉 Step 10 — freegcp0x Result"

# ⭐️ FIXED: Get the REAL URL from gcloud instead of guessing
echo "🔄 Fetching deployed service URL..."
URL_CANONICAL=$(gcloud run services describe "$SERVICE" \
  --region="$REGION" \
  --platform=managed \
  --format='value(status.url)' 2>>"$LOG_FILE")

if [[ -z "$URL_CANONICAL" ]]; then
  err "Failed to get service URL. Check logs."
  exit 1
fi

# ⭐️ FIXED: Extract hostname from the full URL
CANONICAL_HOST=$(echo "$URL_CANONICAL" | sed 's|https://||')

ok "Service Ready"
kv "URL:" "${C_CYAN}${BOLD}${URL_CANONICAL}${RESET}"

# =================== Hidden Protocol URLs ===================
TROJAN_PASS=$(decode_cfg "trojan_pass")
VLESS_UUID=$(decode_cfg "vless_uuid")
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
  vless-ws)   
    URI="vless://${VLESS_UUID}@${TLS_SNI}:${CONN_PORT}?path=${WS_PATH_ENCODED}&security=${SECURITY_TYPE}&encryption=none&host=${CANONICAL_HOST}&type=${NETWORK_TYPE}#Vless-WS" 
    ;;
  vless-grpc) 
    URI="vless://${VLESS_UUID_GRPC}@${TLS_SNI}:${CONN_PORT}?mode=gun&security=${SECURITY_TYPE}&encryption=none&type=grpc&serviceName=${GRPC_SERVICE}&sni=${CANONICAL_HOST}#VLESS-gRPC" 
    ;;
esac

# =================== ⭐️ ADDED: Auto-Delete Setup ===================
banner "🔄 Step 11 — Auto-Delete Setup"
echo "⏰ Setting up auto-delete in ~5 hours..."

CLEANUP_SCRIPT="/tmp/cleanup_${SERVICE}.sh"
cat > "$CLEANUP_SCRIPT" << EOF
#!/bin/bash
sleep $((DELETE_EPOCH - $(date +%s)))
gcloud run services delete "$SERVICE" --region="$REGION" --quiet
echo "✅ Auto-deleted service: $SERVICE at \$(date)"
EOF

chmod +x "$CLEANUP_SCRIPT"
nohup bash "$CLEANUP_SCRIPT" > /tmp/cleanup_${SERVICE}.log 2>&1 &
CLEANUP_PID=$!

ok "Auto-delete scheduled for: ${DELETE_LOCAL} (PID: ${CLEANUP_PID})"

# =================== Telegram Notify ===================
banner "📢 Step 12 — freegcp0x Telegram Notify"

MSG=$(cat <<EOF
<blockquote>GCP V2RAY KEY (${PROTO^^})</blockquote>
<blockquote>Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<pre><code>${URI}</code></pre>

<blockquote>⏳ End: <code>${END_LOCAL}</code></blockquote>
<blockquote>🗑️ Auto-Delete: <code>${DELETE_LOCAL}</code></blockquote>
EOF
)

tg_send "${MSG}"

printf "\n${C_GREEN}${BOLD}✨ freegcp0x Deployment Complete — 2vCPU/2GB Instance Activated${RESET}\n"
printf "${C_GREEN}${BOLD}⏰ 5-Hour Service | Auto-Delete Enabled${RESET}\n"
printf "${C_GREY}📄 Log file: ${LOG_FILE}${RESET}\n"
printf "${C_GREY}🔧 Cleanup PID: ${CLEANUP_PID}${RESET}\n\n"
