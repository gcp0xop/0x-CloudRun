#!/usr/bin/env bash
set -euo pipefail

# ===== Ensure interactive reads =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging =====
LOG_FILE="/tmp/alpha0x1_deploy.log"
touch "$LOG_FILE"

# =================== Color UI ===================
RESET=$'\e[0m'; BOLD=$'\e[1m'
C_CYAN=$'\e[38;5;51m'; C_LIME=$'\e[38;5;118m'
C_PINK=$'\e[38;5;201m'; C_GREY=$'\e[38;5;240m'

banner(){ printf "\n${C_PINK}${BOLD}✨ %s${RESET}\n${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n" "$1"; }
ok(){ printf "   ${C_LIME}✔${RESET} %s\n" "$1"; }
kv(){ printf "   ${C_CYAN}➤ %-12s${RESET} %s\n" "$1" "$2"; }

clear
printf "\n${C_CYAN}${BOLD}🚀 ALPHA 0x1 DEPLOYER${RESET}\n"

# =================== CONFIGURATION ===================
TROJAN_PASS="Alpha-Troj-888"
VLESS_UUID="74272911-3470-495c-8573-240395115189"
SERVICE_NAME_GRPC="Alpha0x1"
IMAGE="docker.io/a0x1/3-in-1:v1"

# =================== Time Setup ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
fmt_time(){ date -d @"$1" "+%I:%M %p"; }
START_FULL="$(fmt_dt "$START_EPOCH")"
JUST_TIME="$(fmt_time "$START_EPOCH")"

# =================== Telegram Setup ===================
banner "🤖 Telegram Setup"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-}"

if [[ -z "$TELEGRAM_TOKEN" ]]; then
  read -rp "   💎 Bot Token: " INPUT_TOKEN
  TELEGRAM_TOKEN="${INPUT_TOKEN:-}"
fi
if [[ -z "$TELEGRAM_CHAT_IDS" ]]; then
  read -rp "   💎 Chat ID:   " INPUT_ID
  TELEGRAM_CHAT_IDS="${INPUT_ID:-}"
fi

tg_send(){
  [[ -z "$TELEGRAM_TOKEN" || -z "$TELEGRAM_CHAT_IDS" ]] && return
  local msg_text="$1"
  for cid in ${TELEGRAM_CHAT_IDS//,/ }; do
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=$cid" \
      --data-urlencode "text=$msg_text" \
      -d "parse_mode=HTML" >/dev/null 2>&1 || true
  done
}

# =================== Project Setup ===================
banner "🏗️ GCP Project"
PROJECT="$(gcloud config get-value project 2>/dev/null)"
if [[ -z "$PROJECT" ]]; then
  echo "❌ No Project found. Run: gcloud config set project <ID>"
  exit 1
fi
kv "Project" "$PROJECT"

# =================== Protocol Selection ===================
banner "🔌 Select Protocol Link"
echo "   1. Trojan WS"
echo "   2. VLESS WS"
echo "   3. VLESS gRPC (ServiceName: Alpha0x1)"
read -rp "   Select [1-3]: " OPTION

# =================== Deploy ===================
banner "🚀 Deploying Alpha0x1..."
SERVICE="alpha0x1"
REGION="us-central1"

gcloud services enable run.googleapis.com --quiet >/dev/null 2>&1

# Note: Added --use-http2 for gRPC support
gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="2Gi" \
  --cpu="2" \
  --allow-unauthenticated \
  --use-http2 \
  --port=8080 \
  --min-instances=1 \
  --quiet >"$LOG_FILE" 2>&1

# =================== Generate Link ===================
URL=$(gcloud run services describe "$SERVICE" --platform=managed --region="$REGION" --format='value(status.url)')
HOST="${URL#https://}"

case "${OPTION:-1}" in
  2) 
    PROTO_NAME="VLESS WS"
    URI="vless://${VLESS_UUID}@vpn.googleapis.com:443?path=%2Fvless&security=tls&encryption=none&host=${HOST}&type=ws#Alpha_VLESS"
    ;;
  3) 
    PROTO_NAME="VLESS gRPC"
    URI="vless://${VLESS_UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${SERVICE_NAME_GRPC}&sni=${HOST}#Alpha_gRPC"
    ;;
  *) 
    PROTO_NAME="Trojan WS"
    URI="trojan://${TROJAN_PASS}@vpn.googleapis.com:443?path=%2Ftrojan&security=tls&host=${HOST}&type=ws#Alpha_Trojan"
    ;;
esac

# =================== Output ===================
banner "🎉 SUCCESS"
kv "Protocol" "$PROTO_NAME"
kv "Domain" "$HOST"
echo ""
echo -e "${C_LIME}${URI}${RESET}"

# =================== Notify ===================
MSG=$(cat <<EOF
<blockquote>🚀 ALPHA 0x1 SERVICE</blockquote>
<blockquote>💎 Premium Server Active</blockquote>
<blockquote>📡 Mytel 4G Supported</blockquote>
<pre><code>${URI}</code></pre>

<blockquote>⏰ Time: <code>${JUST_TIME}</code></blockquote>
<blockquote>📅 Start Time: <code>${START_FULL}</code></blockquote>
EOF
)

tg_send "$MSG"
printf "\n${C_GREY}📄 Log saved to ${LOG_FILE}${RESET}\n"
