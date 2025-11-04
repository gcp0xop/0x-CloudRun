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

printf "\n${C_CYAN}${BOLD}🚀 KSGCP Cloud Run — gRPC Deploy${RESET}\n"
hr

# =================== Simple progress ===================
run_with_progress() {
  local label="$1"; shift
  printf "🔄 %s... " "$label"
  if "$@" >>"$LOG_FILE" 2>&1; then
    printf "✅\n"
  else
    printf "❌\n"
    return 1
  fi
}

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

json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

tg_send(){
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then return 0; fi
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" >>"$LOG_FILE" 2>&1
    ok "Telegram sent → ${_cid}"
  done
}

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
PROTO="grpc"
IMAGE="docker.io/n4pro/grpc:latest"
ok "Protocol selected: gRPC"

# =================== Step 4: Region ===================
banner "🌍 Step 4 — Region Selection"
REGION="us-central1"
ok "Region: ${REGION} (US Central)"

# =================== Step 5: Resources ===================
banner "🧮 Step 5 — Resources"
CPU="4"
MEMORY="4Gi"
ok "CPU/Mem: ${CPU} vCPU / ${MEMORY}"

# =================== Step 6: Service Name ===================
banner "🪪 Step 6 — Service Name"
SERVICE="${SERVICE:-ksgcp-grpc}"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"

read -rp "🔧 Service name [default: ${SERVICE}]: " _svc || true
SERVICE="${_svc:-$SERVICE}"

# Fixed passwords - no input needed
GRPC_PASS="KSGCP-2025"
GRPC_SERVICE_NAME="GService"

ok "Service: ${SERVICE}"
ok "Password: ${GRPC_PASS}" 
ok "gRPC Service: ${GRPC_SERVICE_NAME}"

# =================== Timezone Setup ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"
banner "🕒 Step 7 — Deployment Time"
kv "Start:" "${START_LOCAL}"
kv "End:"   "${END_LOCAL}"

# =================== Enable APIs ===================
banner "⚙️ Step 8 — Enable APIs"
run_with_progress "Enabling CloudRun & Build APIs" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# =================== Deploy ===================
banner "🚀 Step 9 — Deploying to Cloud Run"
echo "🔄 Deploying ${SERVICE} (this may take 2-3 minutes)..."
if gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --timeout="$TIMEOUT" \
  --allow-unauthenticated \
  --port="$PORT" \
  --min-instances=0 \
  --max-instances=1 \
  --quiet >>"$LOG_FILE" 2>&1; then
  ok "Deployment successful"
else
  err "Deployment failed - check log file: $LOG_FILE"
  echo "Last 10 lines of log:"
  tail -10 "$LOG_FILE" >&2
  exit 1
fi

# =================== Result ===================
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"
banner "✅ Result"
ok "Service Ready"
kv "URL:" "${C_CYAN}${BOLD}${URL_CANONICAL}${RESET}"

# =================== gRPC Configuration ===================
GRPC_SNI="${CANONICAL_HOST}"
GRPC_PORT="443"

# Create shareable gRPC link
GRPC_LINK="grpc://${GRPC_SNI}:${GRPC_PORT}?serviceName=${GRPC_SERVICE_NAME}&password=${GRPC_PASS}&sni=${GRPC_SNI}#KSGCP-gRPC"

# =================== Telegram Notify ===================
banner "📣 Step 10 — Telegram Notification"

MSG=$(cat <<EOF
<blockquote>GCP V2RAY KEY</blockquote>
<code>${GRPC_LINK}</code>

⏳ End: ${END_LOCAL}
EOF
)

tg_send "${MSG}"

# Display to user
printf "\n${C_GREEN}${BOLD}✅ gRPC CONFIGURATION:${RESET}\n"
hr
printf "${C_CYAN}${BOLD}gRPC Link:${RESET}\n"
printf "${C_YEL}${GRPC_LINK}${RESET}\n\n"
printf "${C_CYAN}${BOLD}Details:${RESET}\n"
kv "Server" "${GRPC_SNI}"
kv "Port" "${GRPC_PORT}"
kv "Service" "${GRPC_SERVICE_NAME}"
kv "Password" "${GRPC_PASS}"
kv "Resources" "${CPU}vCPU ${MEMORY}"

printf "\n${C_GREEN}${BOLD}✨ Done — KSGCP gRPC Deployed Successfully | 4vCPU 4GB | US Central Region${RESET}\n"
printf "${C_GREY}📄 Log file: ${LOG_FILE}${RESET}\n"
