#!/usr/bin/env bash
# ✨ N4 CloudRun Multi One-Click  
set -euo pipefail
trap 'tput sgr0 2>/dev/null || true; echo; echo "⚠️  Interrupted. Exiting."; exit 1' INT

# ─────────────────── 🎨 Appearance ───────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'
  RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; BLU=$'\e[34m'; CYA=$'\e[36m'; RST=$'\e[0m'
else  BOLD=''; DIM=''; RED=''; GRN=''; YEL=''; BLU=''; CYA=''; RST=''; fi
line(){ printf "%b\n" "${DIM}────────────────────────────────────────────────────────────${RST}"; }
ok(){   printf "%b\n" "${GRN}✔${RST} %s\n" "$*"; }
warn(){ printf "%b\n" "${YEL}▲${RST} %s\n" "$*"; }
err(){  printf "%b\n" "${RED}✖${RST} %s\n" "$*"; }

box(){
  local title="$1"; shift; local body="$*"
  local w; w=$(printf "%s\n" "$body" | awk 'length>max{max=length}END{print max}')
  local pad=$((w+4))
  printf "%b" "${CYA}╔"; printf '%*s' "$pad" | tr ' ' '═'; printf "╗\n${RST}"
  printf "%b" "${CYA}║ ${BOLD}${title}${RST}"; printf '%*s' $((pad-1-${#title})) ""; printf "${CYA}║\n${RST}"
  printf "%b" "${CYA}╠"; printf '%*s' "$pad" | tr ' ' '─'; printf "╣\n${RST}"
  while IFS= read -r line; do printf "%b\n" "${CYA}║ ${line}$(printf '%*s' $((w - ${#line})) '') ${CYA}║${RST}"; done <<< "$body"
  printf "%b" "${CYA}╚"; printf '%*s' "$pad" | tr ' ' '═'; printf "╝\n${RST}"
}

flag_for_region(){
  case "$1" in
    asia-southeast1) echo "🇸🇬";;
    asia-east1)      echo "🇹🇼";;
    asia-northeast1) echo "🇯🇵";;
    us-central1|us-east1|us-west1) echo "🇺🇸";;
    *) echo "🌍";;
  esac
}

# ─────────────────── ✅ Preflight ───────────────────
command -v gcloud >/dev/null 2>&1 || { err "gcloud CLI not found. Please use Google Cloud Shell."; exit 1; }
command -v curl   >/dev/null 2>&1 || { err "curl not found."; exit 1; }
command -v base64 >/dev/null 2>&1 || warn "base64 not found; VMess line may fallback to python."

line
printf "%b\n" "${BOLD}${CYA}🚀 N4 CloudRun Multi One-Click${RST}   ${DIM}(Press Enter to accept defaults)${RST}"
line

# ─────────────────── 🔒 Internal ───────────────────
IMAGE_INTERNAL="${IMAGE_OVERRIDE:-n4vpn/muticore:latest}"   # not printed

# ─────────────────── 🧩 Defaults ───────────────────
SERVICE_DEFAULT="n4vpn"
REGIONS=("us-central1" "us-west1" "us-east1" "asia-southeast1" "asia-east1" "asia-northeast1")
REGION_DEFAULT_IDX=0
CPU_OPTIONS=(1 2 4)
CPU_DEFAULT_IDX=0
MEM_BY_CPU=("2Gi" "4Gi" "8Gi") # 1→2Gi, 2→4Gi, 4→8Gi
TIMEOUT_FIXED=3600

# from container config
UUID_DEFAULT="0c890000-4733-4a0e-9a7f-fc341bd20000"
TROJAN_DEFAULT="trojan-2025"

# ─────────────────── 🧭 Project auto-pick ───────────────────
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${PROJECT}" ]]; then
  warn "No active GCP project configured."
  mapfile -t PJS < <(gcloud projects list --format='value(projectId)' 2>/dev/null || true)
  if [[ ${#PJS[@]} -eq 0 ]]; then
    read -rp "🔑 Enter GCP Project ID: " PROJECT
  else
    echo "📋 Choose your project (index). Enter = 0 (default)"
    for i in "${!PJS[@]}"; do printf "  [%d] %s\n" "$i" "${PJS[$i]}"; done
    read -rp "Project index [0]: " pidx; pidx="${pidx:-0}"
    PROJECT="${PJS[$pidx]}"
  fi
  gcloud config set project "$PROJECT" >/dev/null
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ok "Project: ${PROJECT}"

# ─────────────────── 🧑‍💻 Prompts (Enter = default) ───────────────────
read -rp "🧾 Service name [${SERVICE_DEFAULT}]: " SERVICE; SERVICE="${SERVICE:-$SERVICE_DEFAULT}"

echo "🌍 Region (Asia & US). Enter = ${REGIONS[$REGION_DEFAULT_IDX]}"
for i in "${!REGIONS[@]}"; do tag=" "; [[ $i -eq $REGION_DEFAULT_IDX ]] && tag="*"; printf "  [%d] %s %s\n" "$i" "${REGIONS[$i]}" "$tag"; done
read -rp "Region index [${REGION_DEFAULT_IDX}]: " ridx; ridx="${ridx:-$REGION_DEFAULT_IDX}"; REGION="${REGIONS[$ridx]}"; FLAG="$(flag_for_region "$REGION")"

echo "🧠 CPU vCores. Enter = ${CPU_OPTIONS[$CPU_DEFAULT_IDX]} vCPU"
for i in "${!CPU_OPTIONS[@]}"; do tag=" "; [[ $i -eq $CPU_DEFAULT_IDX ]] && tag="*"; printf "  [%d] %s vCPU %s\n" "$i" "${CPU_OPTIONS[$i]}" "$tag"; done
read -rp "CPU index [${CPU_DEFAULT_IDX}]: " cidx; cidx="${cidx:-$CPU_DEFAULT_IDX}"; CPU="${CPU_OPTIONS[$cidx]}"; MEMORY="${MEM_BY_CPU[$cidx]}"

# Telegram (optional)
read -rp "🤖 Telegram Bot Token (optional): " TG_TOKEN
read -rp "👤 Telegram Owner Chat ID (optional): " TG_CHAT
TG_TOKEN="$(printf '%s' "${TG_TOKEN}" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//' -e 's/\r$//')"
TG_CHAT="$(printf '%s' "${TG_CHAT}" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//' -e 's/\r$//')"

# ─────────────────── ⚙️ Enable Required APIs ───────────────────
echo "🔍 Checking required Google APIs..."
if ! gcloud services list --enabled --format="value(config.name)" | grep -q "run.googleapis.com"; then
  echo "🟡 Enabling Cloud Run API..."
  gcloud services enable run.googleapis.com --quiet
fi
if ! gcloud services list --enabled --format="value(config.name)" | grep -q "cloudbuild.googleapis.com"; then
  echo "🟡 Enabling Cloud Build API..."
  gcloud services enable cloudbuild.googleapis.com --quiet
fi
ok "✅ Required APIs Enabled"

# ─────────────────── 📦 Summary ───────────────────
SUMMARY=$(
cat <<EOF
Project : ${PROJECT}
Service : ${SERVICE}
Region  : ${FLAG} ${REGION}
Image   : (N4 Muti Protocols)
CPU/RAM : ${CPU} vCPU / ${MEMORY}
Timeout : ${TIMEOUT_FIXED}s (fixed)
UUID    : (configured default)
Trojan  : (configured default)
EOF
)
box "✅ Ready to Deploy — Enter to continue  |  Ctrl+C to cancel" "$SUMMARY"
read -rp "" _

# ─────────────────── 🚀 Deploy ───────────────────
echo "⏳ Deploying to Cloud Run…"
gcloud run deploy "${SERVICE}" \
  --image="${IMAGE_INTERNAL}" \
  --platform=managed \
  --region="${REGION}" \
  --port=8080 \
  --allow-unauthenticated \
  --timeout="${TIMEOUT_FIXED}" \
  --cpu="${CPU}" \
  --memory="${MEMORY}" \
  --ingress=all >/dev/null
ok "Deployed."

# ─────────────────── ✅ Canonical URL ───────────────────
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
DOMAIN="${CANONICAL_HOST}"
URL="https://${CANONICAL_HOST}"
ok "Service URL (canonical): ${URL}"

# ─────────────────── 🔗 Client URLs ───────────────────
UUID="${UUID_DEFAULT}"
TROJAN_PASS="${TROJAN_DEFAULT}"
ENC_GRP="N4%20VPN%20gRPC"; ENC_WS="N4%20VPN%20WS"; ENC_TRJ="N4%20Trojan%20gRPC"; ENC_VMS="N4%20VMess%20WS"

VLESS_GRPC="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=grpc&serviceName=grpc-cloudrun&sni=${DOMAIN}#${ENC_GRP}"
VLESS_WS="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&path=%2Fws-cloudrun&host=${DOMAIN}&sni=${DOMAIN}#${ENC_WS}"
TROJAN_GRPC="trojan://${TROJAN_PASS}@${DOMAIN}:443?security=tls&type=grpc&serviceName=trojan-grpc&sni=${DOMAIN}#${ENC_TRJ}"

VMESS_JSON=$(cat <<EOF
{"v":"2","ps":"N4 VMess WS","add":"${DOMAIN}","port":"443","id":"${UUID}","aid":"0","net":"ws","type":"none","host":"${DOMAIN}","path":"/vmess-ws","tls":"tls","sni":"${DOMAIN}"}
EOF
)
if command -v base64 >/dev/null 2>&1; then
  VMESS_B64="$(printf '%s' "$VMESS_JSON" | base64 | tr -d '\n')"
else
  VMESS_B64="$(python3 - <<PY
import sys,base64
print(base64.b64encode(sys.stdin.read().encode()).decode())
PY
<<<"$VMESS_JSON")"
fi
VMESS_WS="vmess://${VMESS_B64}"

# ─────────────────── ⏱️ Time (Asia/Yangon) — Start + 5 hours ───────────────────
TZ=Asia/Yangon
START_TS="$(TZ=$TZ date +%s)"
END_TS="$(( START_TS + 5*3600 ))"
START_HUMAN="$(TZ=$TZ date -d "@$START_TS" '+%Y-%m-%d %I:%M %p' 2>/dev/null || TZ=$TZ date -r "$START_TS" '+%Y-%m-%d %I:%M %p')"
END_HUMAN="$(TZ=$TZ date -d "@$END_TS" '+%Y-%m-%d %I:%M %p'  2>/dev/null || TZ=$TZ date -r "$END_TS"  '+%Y-%m-%d %I:%M %p')"

# ─────────────────── 🖨️ Console Output ───────────────────
box "🔗 N4 Links — copy & paste" "1) VLESS gRPC
${VLESS_GRPC}

2) VLESS WS
${VLESS_WS}

3) TROJAN gRPC
${TROJAN_GRPC}

4) VMESS WS
${VMESS_WS}

🕒 Start : ${START_HUMAN}
⏳ Expire: ${END_HUMAN}
🧠 CPU   : ${CPU} vCPU
💾 RAM   : ${MEMORY}
📍 Region: ${FLAG} ${REGION}
🌐 URL   : ${URL}"

# ─────────────────── 📨 Telegram (All HTML <pre><code> blocks) ───────────────────
tg_html_escape(){ sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
tg_send_html(){
  local token="$1" chat="$2" text="$3"
  curl -fsS "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=${chat}" \
    --data-urlencode "text=${text}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null
}

if [[ -n "${TG_TOKEN:-}" && -n "${TG_CHAT:-}" ]]; then
  SERVICE_INFO=$(
    cat <<TXT
📦 Service Info
Project: ${PROJECT}
Service: ${SERVICE}
URL: ${URL}
Region: ${FLAG} ${REGION}
CPU/RAM: ${CPU} vCPU / ${MEMORY}
Start: ${START_HUMAN}
Expire: ${END_HUMAN}
TXT
  )
  tg_send_html "$TG_TOKEN" "$TG_CHAT" "<b>✅ Deploy Successful</b>
<pre><code>$(printf '%s' "$SERVICE_INFO" | tg_html_escape)</code></pre>" || warn "Header failed"

  tg_send_html "$TG_TOKEN" "$TG_CHAT" "<b>VLESS gRPC</b>
<pre><code>$(printf '%s' "$VLESS_GRPC" | tg_html_escape)</code></pre>"
  tg_send_html "$TG_TOKEN" "$TG_CHAT" "<b>VLESS WS</b>
<pre><code>$(printf '%s' "$VLESS_WS" | tg_html_escape)</code></pre>"
  tg_send_html "$TG_TOKEN" "$TG_CHAT" "<b>TROJAN gRPC</b>
<pre><code>$(printf '%s' "$TROJAN_GRPC" | tg_html_escape)</code></pre>"
  tg_send_html "$TG_TOKEN" "$TG_CHAT" "<b>VMESS WS</b>
<pre><code>$(printf '%s' "$VMESS_WS" | tg_html_escape)</code></pre>"

  ok "Telegram messages sent (HTML code blocks) ✅"
else
  warn "Telegram not configured (skipped)."
fi

line
printf "%b\n" "${BOLD}${GRN}🎉 Done.${RST} Paste the links into your client.   ${DIM}(Docker image hidden)${RST}"
line
