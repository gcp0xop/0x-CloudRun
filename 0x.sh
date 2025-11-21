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
banner(){
  local title="$1"
  printf "\n${C_PINK}${BOLD}✨ %s${RESET}\n${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n" "$title"
}
ok(){   printf "   ${C_LIME}✔${RESET} %s\n" "$1"; }
warn(){ printf "   ${C_ORANGE}⚠${RESET} %s\n" "$1"; }
err(){  printf "   ${C_RED}✘${RESET} %s\n" "$1"; }
kv(){   printf "   ${C_CYAN}➤ %-12s${RESET} ${C_WHITE}%s${RESET}\n" "$1" "$2"; }

clear
printf "\n${C_PURPLE}${BOLD}🚀 KSGCP CLOUD RUN DEPLOYER${RESET} ${C_ORANGE}(Premium Edition)${RESET}\n"
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
      printf "\r   ${C_YELLOW}${spin:$i:1}${RESET} %s..." "$label"
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

read -rp "   ${C_PURPLE}💎 Bot Token:${RESET} " _tk || true
[[ -n "${_tk:-}" ]] && TELEGRAM_TOKEN="$_tk"
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then
  warn "Token empty! No notifications will be sent."
else
  ok "Token saved."
fi

read -rp "   ${C_PURPLE}💎 Chat ID:${RESET}   " _ids || true
[[ -n "${_ids:-}" ]] && TELEGRAM_CHAT_IDS="${_ids// /}"

BTN_LABELS=(); BTN_URLS=()

read -rp "   ${C_ORANGE}➕ Add Buttons? [y/N]:${RESET} " _addbtn || true
if [[ "${_addbtn:-}" =~ ^([yY]|yes)$ ]]; then
  i=0
  while true; do
    echo "   ${C_GREY}—— Button $((i+1)) ——${RESET}"
    read -rp "   🏷️ Label: " _lbl || true
    if [[ -z "${_lbl:-}" ]]; then
      warn "Skipped."
    else
      read -rp "   🔗 URL:   " _url || true
      if [[ -n "${_url:-}" && "${_url}" =~ ^https?:// ]]; then
        BTN_LABELS+=("${_lbl}")
        BTN_URLS+=("${_url}")
        ok "Added: ${_lbl}"
      else
        warn "Invalid URL."
      fi
    fi
    i=$(( i + 1 ))
    (( i >= 3 )) && break
    read -rp "   ➕ Add another? [y/N]: " _more || true
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

# =================== Step 3: Protocol ===================
banner "🔌 Step 3 — Select Protocol"
echo "   ${C_CYAN}1.${RESET} Trojan WS"
echo "   ${C_CYAN}2.${RESET} VLESS WS"
echo "   ${C_CYAN}3.${RESET} VLESS gRPC"
read -rp "   ${C_YELLOW}Select [1-3]:${RESET} " _opt || true
case "${_opt:-1}" in
  2) PROTO="vless-ws"   ; IMAGE="docker.io/n4pro/vl:latest"        ;;
  3) PROTO="vless-grpc" ; IMAGE="docker.io/n4pro/vlessgrpc:latest" ;;
  *) PROTO="trojan-ws"  ; IMAGE="docker.io/n4pro/tr:latest"        ;;
esac
ok "Selected: ${PROTO^^}"

# =================== Step 4: Region (Fixed) ===================
REGION="us-central1"

# =================== Step 5: Resources (Fixed) ===================
CPU="4"
MEMORY="2Gi"

# =================== Step 6: Service Name (FIXED) ===================
# Per request: Fixed to 'ksgcp' only.
SERVICE="ksgcp"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"

banner "⚙️ Step 4 — Configuration"
kv "Region" "${REGION}"
kv "Service" "${SERVICE} (Fixed)"
kv "Specs" "${CPU} CPU / ${MEMORY} RAM"

# =================== Timezone Setup ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))" # 5 hours later
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"

banner "🕒 Step 5 — Deployment Time"
kv "Start:" "${START_LOCAL}"
kv "End:"   "${END_LOCAL}"

# =================== Enable APIs ===================
banner "🔧 Step 6 — Setup APIs"
run_with_progress "Enabling CloudRun API" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# =================== Deploy ===================
banner "🚀 Step 7 — Deploying"
run_with_progress "Pushing ${SERVICE} to Cloud Run" \
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

banner "🎉 FINAL RESULT"
kv "Status" "Active"
kv "Domain" "${URL_CANONICAL}"

# =================== Protocol URLs ===================
TROJAN_PASS="Trojan-2025"
VLESS_UUID="0c890000-4733-b20e-067f-fc341bd20000"
VLESS_UUID_GRPC="0c890000-4733-4a0e-9a7f-fc341bd20000"

case "$PROTO" in
  trojan-ws)  URI="trojan://${TROJAN_PASS}@vpn.googleapis.com:443?path=%2FN4&security=tls&host=${CANONICAL_HOST}&type=ws#KS_GCP" ;;
  vless-ws)   URI="vless://${VLESS_UUID}@vpn.googleapis.com:443?path=%2FN4&security=tls&encryption=none&host=${CANONICAL_HOST}&type=ws#KS_GCP" ;;
  vless-grpc) URI="vless://${VLESS_UUID_GRPC}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=n4-grpc&sni=${CANONICAL_HOST}#KS_GCP" ;;
esac

# =================== Telegram Notify ===================
banner "📨 Step 8 — Sending Notification"

MSG=$(cat <<EOF
<blockquote>🚀 KSGCP V2RAY SERVICE</blockquote>
<blockquote>💎 Premium Server Active</blockquote>
<blockquote>📡 Mytel 4G Supported</blockquote>
<pre><code>${URI}</code></pre>

<blockquote>✅ စတင်ချိန်: <code>${START_LOCAL}</code></blockquote>
<blockquote>❌ ပြီးဆုံးမယ့် အချိန် (ခန့်မှန်း): <code>${END_LOCAL}</code></blockquote>
EOF
)

tg_send "${MSG}"

printf "\n${C_LIME}${BOLD}✅ ALL DONE! Enjoy your KSGCP Server.${RESET}\n"
printf "${C_GREY}📄 Log: ${LOG_FILE}${RESET}\n"
