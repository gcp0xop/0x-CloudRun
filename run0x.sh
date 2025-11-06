#!/usr/bin/env bash
set -euo pipefail

# ===== Hidden Configuration (Base64 Encoded) =====
HIDDEN_CFG="ewogICJ0cm9qYW5fcGFzcyI6ICJUcm9qYW4tMjAyNSIsCiAgInZsZXNzX3V1aWQiOiAiMGM4OTAwMDAtNDczMy1iMjBlLTA2N2YtZmMzNDFiZDIwMDAwIiwKICAidmxlc3NfdXVpZF9ncnBjIjogIjBjODkwMDAwLTQ3MzMtNGEwZS05YTdmLWZjMzQxYmQyMDAwMCIsCiAgIndzX3BhdGgiOiAiL040IiwKICAiZ3JwY19zZXJ2aWNlIjogIm40LWdycGMiLAogICJ0bHNfc25pIjogInZwbi5nb29nbGVhcGlzLmNvbSIsCiAgInBvcnQiOiAiNDQzIiwKICAibmV0d29yayI6ICJ3cyIsCiAgInNlY3VyaXR5IjogInRscyIKfQo="

decode_cfg() { 
  if command -v jq >/dev/null 2>&1; then
    echo "$HIDDEN_CFG" | base64 -d 2>/dev/null | jq -r ".$1" 2>/dev/null
  else
    # Fallback if jq not available
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
  fi
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
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO" | tee -a "$LOG_FILE" >&2
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

# =================== Fixed Progress Spinner ===================
run_with_progress() {
  local label="$1"; shift
  echo "🔄 ${label}..." | tee -a "$LOG_FILE"
  
  # Run command and capture output
  if ("$@" >> "$LOG_FILE" 2>&1); then
    echo "✅ ${label} completed" | tee -a "$LOG_FILE"
    return 0
  else
    local rc=$?
    echo "❌ ${label} failed (exit code: $rc)" | tee -a "$LOG_FILE"
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
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
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
REGION="us-central1"
ok "Auto-selected Region: ${REGION}"

# =================== Step 5: Resources ===================
banner "💪 Step 5 — freegcp0x Resources"
echo "💡 Auto-set: 2 vCPU / 2GB Memory (Optimized Tier)"
CPU="2"
MEMORY="2Gi"
ok "CPU/Mem: ${CPU} vCPU / ${MEMORY}"

# =================== Step 6: Service Name ===================
banner "🏷️ Step 6 — freegcp0x Service Name"
SERVICE="KS_GCP"
TIMEOUT="${TIMEOUT:-19800}"  # ✅ 5 hours 30 minutes = 19800 seconds
PORT="${PORT:-8080}"
ok "Auto-set Service Name: ${SERVICE}"

# =================== Timezone Setup ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"
banner "⏰ Step 7 — freegcp0x Deployment Time"
kv "Start:" "${START_LOCAL}"
kv "End:"   "${END_LOCAL}"

# =================== Enable APIs ===================
banner "🔧 Step 8 — freegcp0x Enable APIs"
run_with_progress "Enabling CloudRun & Build APIs" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# =================== Deploy ===================
banner "🚀 Step 9 — freegcp0x Deploying to Cloud Run"
run_with_progress "Deploying ${SERVICE}" \
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
    --quiet

# =================== Result ===================
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"
banner "🎉 Step 10 — freegcp0x Result"
ok "Service Ready"
kv "URL:" "${C_CYAN}${BOLD}${URL_CANONICAL}${RESET}"

# =================== Hidden Protocol URLs ===================
# All sensitive configuration is now hidden
TROJAN_PASS=$(decode_cfg "trojan_pass")           # ✅ Hidden - "Trojan-2025"
VLESS_UUID=$(decode_cfg "vless_uuid")             # ✅ Hidden - "0c890000-4733-b20e-067f-fc341bd20000"
VLESS_UUID_GRPC=$(decode_cfg "vless_uuid_grpc")   # ✅ Hidden - "0c890000-4733-4a0e-9a7f-fc341bd20000"
WS_PATH=$(decode_cfg "ws_path")                   # ✅ Hidden - "/N4"
GRPC_SERVICE=$(decode_cfg "grpc_service")         # ✅ Hidden - "n4-grpc"
TLS_SNI=$(decode_cfg "tls_sni")                   # ✅ Hidden - "vpn.googleapis.com"
CONN_PORT=$(decode_cfg "port")                    # ✅ Hidden - "443"
NETWORK_TYPE=$(decode_cfg "network")              # ✅ Hidden - "ws"
SECURITY_TYPE=$(decode_cfg "security")            # ✅ Hidden - "tls"

# URL encode the path for the URI
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

# =================== Telegram Notify ===================
banner "📢 Step 11 — freegcp0x Telegram Notify"

MSG=$(cat <<EOF
<blockquote>GCP V2RAY KEY
</blockquote>
<blockquote>Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်
</blockquote>

<pre><code>${URI}</code></pre>

<blockquote>⏳ End: <code>${END_LOCAL}</code></blockquote>
EOF
)

tg_send "${MSG}"

printf "\n${C_GREEN}${BOLD}✨ freegcp0x Deployment Complete — 2vCPU/2GB Optimized Instance Activated${RESET}\n"
printf "${C_GREY}📄 Log file: ${LOG_FILE}${RESET}\n"
