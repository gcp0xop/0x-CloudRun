#!/usr/bin/env bash
set -euo pipefail

# ===== NEON UI THEME =====
if [[ -t 1 ]]; then
  RESET=$'\e[0m'
  BOLD=$'\e[1m'
  # Neon Palette
  NEON_PINK=$'\e[38;5;198m'
  NEON_CYAN=$'\e[38;5;51m'
  NEON_LIME=$'\e[38;5;118m'
  NEON_YELLOW=$'\e[38;5;226m'
  NEON_RED=$'\e[38;5;196m'
  NEON_WHITE=$'\e[38;5;231m'
else
  RESET= BOLD= NEON_PINK= NEON_CYAN= NEON_LIME= NEON_YELLOW= NEON_RED= NEON_WHITE=
fi

# ===== Helper Functions =====
line(){ printf "${NEON_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"; }
banner(){
  echo ""
  printf "${NEON_PINK}${BOLD}✨ %s${RESET}\n" "$1"
  line
}
info(){ printf "   ${NEON_YELLOW}➤ %-12s${RESET} ${NEON_WHITE}%s${RESET}\n" "$1" "$2"; }
ok(){   printf "   ${NEON_LIME}✅ %s${RESET}\n" "$1"; }
err(){  printf "   ${NEON_RED}❌ %s${RESET}\n" "$1"; exit 1; }

# ===== Header =====
clear
printf "\n${NEON_PINK}${BOLD}🚀 ALPHA0x1 NEON DEPLOYER${RESET} ${NEON_LIME}(Ultimate Edition)${RESET}\n"
line

# =================== Step 1: Telegram Setup ===================
banner "🤖 Step 1 — Telegram Setup"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-}"

# Auto-detect or ask (Clean Interface)
if [[ -z "${TELEGRAM_TOKEN}" ]]; then
  read -rp "   ${NEON_PINK}💎 Bot Token:${RESET} " _tk || true
  [[ -n "${_tk}" ]] && TELEGRAM_TOKEN="$_tk"
else
  ok "Token Detected"
fi

if [[ -z "${TELEGRAM_CHAT_IDS}" ]]; then
  read -rp "   ${NEON_PINK}💎 Chat ID:${RESET}   " _ids || true
  [[ -n "${_ids}" ]] && TELEGRAM_CHAT_IDS="${_ids// /}"
else
  ok "Chat ID Detected"
fi

tg_send(){
  local text="$1"
  [[ -z "${TELEGRAM_TOKEN}" || -z "${TELEGRAM_CHAT_IDS}" ]] && return 0
  IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" --data-urlencode "text=${text}" -d "parse_mode=HTML" >/dev/null 2>&1 || true
  done
}

# =================== Step 2: Project Check ===================
banner "🏗️ Step 2 — Checking Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"

# Smart Fix for Unset Project
if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  printf "   ${NEON_YELLOW}⚠️ Project ID missing. Attempting auto-fix...${RESET}\n"
  PROJECT="${DEVSHELL_PROJECT_ID:-}"
  if [[ -z "$PROJECT" ]]; then
     read -rp "   👉 Enter Project ID manually: " PROJECT
  fi
fi

if [[ -z "$PROJECT" ]]; then err "Project ID Required!"; fi

gcloud config set project "$PROJECT" --quiet >/dev/null 2>&1
info "Project" "${PROJECT}"

# =================== Step 3: Configuration ===================
banner "⚙️ Step 3 — Server Config"

# --- CUSTOM SETTINGS ---
IMAGE="docker.io/a0x1/al0x1:latest"
SERVICE="alpha0x1"
SERVICE_NAME="Tg-@Alpha0x1"           # <--- Requested Name
REGION="us-central1"
CPU="4"
MEMORY="4Gi"
UUID="$(cat /proc/sys/kernel/random/uuid)"
# -----------------------

info "Docker"    "${IMAGE}"
info "Service"   "${SERVICE_NAME}"
info "Spec"      "${CPU} CPU / ${MEMORY} RAM"
info "Region"    "US Central (dl.google.com)"

# =================== Step 4: Deploy ===================
banner "🚀 Step 4 — Deploying (Max 2 Instances)"

# Enable APIs silently
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet >/dev/null 2>&1

printf "   ${NEON_CYAN}⏳ Pushing to Google Cloud... Please wait...${RESET}\n"

# Deploy Command
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
  --port=8080 \
  --min-instances=1 \
  --max-instances=2 \
  --concurrency=500 \
  --quiet >/dev/null 2>&1

# Check Status
URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)' 2>/dev/null || true)"

if [[ -z "$URL" ]]; then err "Deployment Failed! Check Cloud Run logs."; fi

HOST="${URL#https://}"

# === LINK GENERATION (dl.google.com + Custom ServiceName) ===
URI="vless://${UUID}@dl.google.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${SERVICE_NAME}&sni=${HOST}#Alpha0x1"

# =================== Step 5: Final Result ===================
# Timezone
export TZ="Asia/Yangon"
START_LOCAL="$(date "+%d.%m.%Y %I:%M %p")"
END_LOCAL="$(date -d "+5 hours" "+%d.%m.%Y %I:%M %p")"

banner "🎉 FINAL RESULT"
info "Status"  "Active (VIP Line)"
info "Address" "dl.google.com"
info "Path"    "${SERVICE_NAME}"
echo ""
printf "   ${NEON_PINK}👇 COPY THIS LINK 👇${RESET}\n"
printf "   ${NEON_WHITE}%s${RESET}\n" "${URI}"
echo ""

# =================== Telegram Notify ===================
banner "📨 Step 6 — Sending Notification"

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
ok "Notification Sent!"

printf "\n${NEON_LIME}${BOLD}✅ ALL DONE! Enjoy your Alpha0x1 Server.${RESET}\n"
