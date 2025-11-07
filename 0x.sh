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

# =================== Color & UI (KSGCP Theme) ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
  C_PURPLE=$'\e[38;5;99m'  # For banners
  C_GOLD=$'\e[38;5;214m'   # For title and highlights
  C_GREEN=$'\e[38;5;46m'  # OK
  C_ORG=$'\e[38;5;208m'   # Warn
  C_GREY=$'\e[38;5;245m'  # Dim
  C_RED=$'\e[38;5;196m'   # Error
else
  RESET= BOLD= DIM= C_PURPLE= C_GOLD= C_GREEN= C_ORG= C_GREY= C_RED=
fi

hr(){ printf "${C_GOLD}%s${RESET}\n" "══════════════════════════════════════════════════"; }
banner(){
  local title="$1"
  printf "\n${C_PURPLE}${BOLD}╔══════════════════════════════════════════════════╗${RESET}\n"
  printf   "${C_PURPLE}${BOLD}║${RESET}  %s${RESET}\n" "$(printf "%-46s" "$title")"
  printf   "${C_PURPLE}${BOLD}╚══════════════════════════════════════════════════╝${RESET}\n"
}
ok(){   printf "${C_GREEN}✔${RESET} %s\n" "$1"; }
warn(){ printf "${C_ORG}⚠${RESET} %s\n" "$1"; }
err(){  printf "${C_RED}✘${RESET} %s\n" "$1"; }
kv(){   printf "   ${C_GREY}%s${RESET}  %s\n" "$1" "$2"; }

printf "\n${C_GOLD}${BOLD}🚀 KSGCP Cloud Run — One-Click Deploy${RESET} ${C_GREY}(Trojan WS / VLESS WS / VLESS gRPC)${RESET}\n"
hr

# =================== Random progress spinner ===================
run_with_progress() {
  local label="$1"; shift
  ( "$@" ) >>"$LOG_FILE" 2>&1 &
  local pid=$!
  local pct=5
  if [[ -t 1 ]]; then
    printf "\e[?25l"
    while kill -0 "$pid" 2>/dev/null; do
      local step=$(( (RANDOM % 9) + 2 ))
      pct=$(( pct + step ))
      (( pct > 95 )) && pct=95
      printf "\r🌀 %s... [%s%%]" "$label" "$pct"
      sleep "$(awk -v r=$RANDOM 'BEGIN{s=0.08+(r%7)/100; printf "%.2f", s }')"
    done
    wait "$pid"; local rc=$?
    printf "\r"
    if (( rc==0 )); then
      printf "✅ %s... [100%%]\n" "$label"
    else
      printf "❌ %s failed (see %s)\n" "$label" "$LOG_FILE"
      return $rc
    fi
    printf "\e[?25h"
  else
    wait "$pid"
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

DEFAULT_LABEL="Join KSGCP Channel"
DEFAULT_URL="https://t.me/ksgcp_channel" # <-- Placeholder URL
BTN_LABELS=(); BTN_URLS=()

read -rp "➕ Add URL button(s)? [y/N]: " _addbtn || true
if [[ "${_addbtn:-}" =~ ^([yY]|yes)$ ]]; then
  i=0
  while true; do
    echo "—— Button $((i+1)) ——"
    read -rp "🔖 Label [default: ${DEFAULT_LABEL}]: " _lbl || true
    if [[ -z "${_lbl:-}" ]]; then
      BTN_LABELS+=("${DEFAULT_LABEL}")
      BTN_URLS+=("${DEFAULT_URL}")
      ok "Added: ${DEFAULT_LABEL} → ${DEFAULT_URL}"
    else
      read -rp "🔗 URL (http/https): " _url || true
      if [[ -n "${_url:-}" && "${_url}" =~ ^https?:// ]]; then
        BTN_LABELS+=("${_lbl}")
        BTN_URLS+=("${_url}")
        ok "Added: ${_lbl} → ${_url}"
      else
        warn "Skipped (invalid or empty URL)."
      fi
    fi
    i=$(( i + 1 ))
    (( i >= 3 )) && break
    read -rp "➕ Add another button? [y/N]: " _more || true
    [[ "${_more:-}" =~ ^([yY]|yes)$ ]] || break
  done
fi

CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS:-}" || true

json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

tg_send(){
  local text="$1" RM=""
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then return 0; fi
  if (( ${#BTN_LABELS[@]} > 0 )); then
    local L1 U1 L2 U2 L3 U3
    [[ -n "${BTN_LABELS[0]:-}" ]] && L1="$(json_escape "${BTN_LABELS[0]}")" && U1="$(json_escape "${BTN_URLS[0]}")"
    [[ -n "${BTN_LABELS[1]:-}" ]] && L2="$(json_escape "${BTN_LABELS[1]}")" && U2="$(json_escape "${BTN_URLS[1]}")"
    [[ -n "${BTN_LABELS[2]:-}" ]] && L3="$(json_escape "${BTN_LABELS[2]}")" && U3="$(json_escape "${BTN_URLS[2]}")"
    if (( ${#BTN_LABELS[@]} == 1 )); then
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}]]}"
    elif (( ${#BTN_LABELS[@]} == 2 )); then
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}],[{\"text\":\"${L2}\",\"url\":\"${U2}\"}]]}"
    else
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}],[{\"text\":\"${L2}\",\"url\":\"${U2}\"},{\"text\":\"${L3}\",\"url\":\"${U3}\"}]]}"
    fi
  fi
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" \
      ${RM:+--data-urlencode "reply_markup=${RM}"} >>"$LOG_FILE" 2>&1
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
banner "🧩 Step 3 — Select Protocol"
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

# =================== Step 4: Region (Auto-set) ===================
banner "🌍 Step 4 — Region"
REGION="us-central1"
ok "Region: ${REGION} (Auto-set)"

# =================== Step 5: Resources (Auto-set) ===================
banner "🧮 Step 5 — Resources"
CPU="2"
MEMORY="2Gi"
ok "CPU/Mem: ${CPU} vCPU / ${MEMORY} (Auto-set)"

# =================== Step 6: Service Name ===================
banner "🪪 Step 6 — Service Name"
SERVICE="${SERVICE:-ksgcp-vpn}"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"
read -rp "Service name [default: ${SERVICE}]: " _svc || true
SERVICE="${_svc:-$SERVICE}"
ok "Service: ${SERVICE}"

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
banner "✅ Result"
ok "Service Ready"
kv "URL:" "${C_GOLD}${BOLD}${URL_CANONICAL}${RESET}"

# =================== Protocol URLs ===================
TROJAN_PASS="Trojan-2025"
VLESS_UUID="0c890000-4733-b20e-067f-fc341bd20000"
VLESS_UUID_GRPC="0c890000-4733-4a0e-9a7f-fc341bd20000"

case "$PROTO" in
  trojan-ws)  URI="trojan://${TROJAN_PASS}@vpn.googleapis.com:443?path=%2FN4&security=tls&host=${CANONICAL_HOST}&type=ws#KSGCP-Trojan" ;;
  vless-ws)   URI="vless://${VLESS_UUID}@vpn.googleapis.com:443?path=%2FN4&security=tls&encryption=none&host=${CANONICAL_HOST}&type=ws#KSGCP-Vless" ;;
  vless-grpc) URI="vless://${VLESS_UUID_GRPC}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=n4-grpc&sni=${CANONICAL_HOST}#KSGCP-gRPC" ;;
esac

# =================== Telegram Notify ===================
banner "📣 Step 10 — Telegram Notify"

MSG=$(cat <<EOF
<blockquote>🚀 KSGCP V2RAY KEY
</blockquote>
<blockquote>Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်
</blockquote>

<pre><code>${URI}</code></pre>

<blockquote>⏳ End
: <code>${END_LOCAL}</code></blockquote>
EOF
)

tg_send "${MSG}"

printf "\n${C_GOLD}${BOLD}✨ Done — Warm Instance Enabled (min=1) | KSGCP UI | Cold Start Prevented${RESET}\n"
printf "${C_GREY}📄 Log file: ${LOG_FILE}${RESET}\n"
