#!/usr/bin/env bash
set -euo pipefail

# ========== Ensure interactive reads even when run via curl/process substitution ==========
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

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
sec(){ printf "\n${C_BLUE}📦 ${BOLD}%s${RESET}\n" "$1"; hr; }
ok(){ printf "${C_GREEN}✔${RESET} %s\n" "$1"; }
warn(){ printf "${C_ORG}⚠${RESET} %s\n" "$1"; }
err(){ printf "${C_RED}✘${RESET} %s\n" "$1"; }
kv(){ printf "   ${C_GREY}%s${RESET}  %s\n" "$1" "$2"; }

printf "\n${C_CYAN}${BOLD}🚀 N4 Cloud Run — One-Click Deploy${RESET} ${C_GREY}(Trojan gRPC / VLESS WS / VLESS gRPC / VMess WS)${RESET}\n"
hr

# =================== Telegram Config ===================
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-${TELEGRAM_CHAT_ID:-}}"

# .env fallback (only if missing)
if [[ ( -z "${TELEGRAM_TOKEN}" || -z "${TELEGRAM_CHAT_IDS}" ) && -f .env ]]; then
  set -a; source ./.env; set +a
fi

printf "\n${C_PINK}${BOLD}Telegram Setup${RESET}\n"
echo "   Note: Token input is hidden (no characters will show)."
read -rsp "   🤖 Telegram Bot Token: " _tk || true; echo
if [[ -n "${_tk:-}" ]]; then TELEGRAM_TOKEN="$_tk"; fi
[[ -n "${TELEGRAM_TOKEN:-}" ]] && ok "Telegram token captured (hidden)."

read -rp "   👤 Owner/Channel Chat ID(s) (comma-separated): " _ids || true
if [[ -n "${_ids:-}" ]]; then TELEGRAM_CHAT_IDS="${_ids// /}"; fi

# ----- URL Buttons (optional, up to 3) -----
DEFAULT_LABEL="Join N4 VPN Channel"
DEFAULT_URL="https://t.me/n4vpn"
BTN_LABELS=()
BTN_URLS=()

read -rp "   ➕ Add URL button(s)? [y/N]: " _addbtn || true
if [[ "${_addbtn:-}" =~ ^([yY]|yes)$ ]]; then
  i=0
  while (( i < 3 )); do
    echo "   —— Button $((i+1)) ——"
    read -rp "   🔖 Button Label [default: ${DEFAULT_LABEL}]: " _lbl || true
    if [[ -z "${_lbl:-}" ]]; then
      BTN_LABELS+=("${DEFAULT_LABEL}")
      BTN_URLS+=("${DEFAULT_URL}")
      ok "Added: ${DEFAULT_LABEL} → ${DEFAULT_URL}"
    else
      while :; do
        read -rp "   🔗 Button URL (http/https): " _url || true
        if [[ -n "${_url:-}" && "${_url}" =~ ^https?:// ]]; then
          BTN_LABELS+=("${_lbl}")
          BTN_URLS+=("${_url}")
          ok "Added: ${_lbl} → ${_url}"
          break
        else
          warn "Please enter a valid http(s) URL."
        fi
      done
    fi
    ((i++))
    (( i >= 3 )) && break
    read -rp "   ➕ Add another button? [y/N]: " _more || true
    [[ "${_more:-}" =~ ^([yY]|yes)$ ]] || break
  done
fi

# Build receivers array (avoid set -e exit)
CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS:-}" || true

# Telegram send helper (attach inline buttons if any)
tg_send(){
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then
    warn "Telegram not configured (skip send)."
    return 0
  fi

  local RM=""
  if (( ${#BTN_LABELS[@]} > 0 )); then
    local parts=()
    for idx in "${!BTN_LABELS[@]}"; do
      parts+=("{\"text\":\"${BTN_LABELS[$idx]//\"/\\\"}\",\"url\":\"${BTN_URLS[$idx]//\"/\\\"}\"}")
    done
    local row=$(IFS=, ; echo "${parts[*]}")
    RM="{\"inline_keyboard\":[[${row}]]}"
  fi

  for _cid in "${CHAT_ID_ARR[@]}"; do
    if [[ -n "$RM" ]]; then
      curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${_cid}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" \
        --data-urlencode "reply_markup=${RM}" >/dev/null || true
    else
      curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${_cid}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" >/dev/null || true
    fi
  done
}

# =================== Project ===================
sec "Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  err "No active GCP project."
  echo "👉 gcloud config set project <YOUR_PROJECT_ID>"
  exit 1
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ok "Loaded Project"
kv "Project:"       "${BOLD}${PROJECT}${RESET}"
kv "Project No.:"   "${PROJECT_NUMBER}"

# =================== Protocol (exactly 4) ===================
sec "Protocol"
echo "   1) Trojan gRPC"
echo "   2) VLESS WS"
echo "   3) VLESS gRPC"
echo "   4) VMess WS"
read -rp "   Choose [1-4, default 1]: " _opt || true

case "${_opt:-1}" in
  2) PROTO="vless-ws"    ; IMAGE="docker.io/n4vip/vless:latest"        ;;
  3) PROTO="vless-grpc"  ; IMAGE="docker.io/n4vip/vlessgrpc:latest"    ;;
  4) PROTO="vmess-ws"    ; IMAGE="docker.io/n4vip/vmess:latest"        ;;
  *) PROTO="trojan-grpc" ; IMAGE="docker.io/n4vip/trojangrpc:latest"   ;;
esac
ok "Protocol selected: ${PROTO^^}"
kv "Docker Image:" "${IMAGE}"

# =================== Region ===================
sec "Region"
echo "   1) 🇸🇬 Singapore (asia-southeast1)"
echo "   2) 🇺🇸 US (us-central1)"
echo "   3) 🇮🇩 Indonesia (asia-southeast2)"
echo "   4) 🇯🇵 Japan (asia-northeast1)"
read -rp "   Choose [1-4, default 2]: " _r || true
case "${_r:-2}" in
  1) REGION="asia-southeast1";;
  3) REGION="asia-southeast2";;
  4) REGION="asia-northeast1";;
  *) REGION="us-central1";;
esac
ok "Region: ${REGION}"

# =================== CPU & Memory ===================
sec "Resources"
read -rp "   CPU [1/2/4/6, default 2]: " _cpu || true
CPU="${_cpu:-2}"
read -rp "   Memory [512Mi/1Gi/2Gi(default)/4Gi/8Gi]: " _mem || true
MEMORY="${_mem:-2Gi}"
ok "CPU/Mem: ${CPU} vCPU / ${MEMORY}"

# =================== Other defaults ===================
SERVICE="${SERVICE:-freen4vpn}"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"

read -rp "   Service name [default: ${SERVICE}]: " _svc || true
SERVICE="${_svc:-$SERVICE}"

# =================== Keys / Tags / Paths ===================
VLESS_WS_TAG="VLESS WS Protocol"
VLESS_GRPC_TAG="Vless Grpc"

TROJAN_PASS="Nanda"
TROJAN_GRPC_SVC="n4trojan-grpc"
TROJAN_GRPC_TAG="GCP TROJAN gRPC"

VLESS_UUID="0c890000-4733-b20e-067f-fc341bd20000"
VLESS_PATH_WS="%2FN4VPN"

VLESS_UUID_GRPC="0c890000-4733-b20e-067f-fc341bd20000"
VLESS_GRPC_SVC="n4vpnfree-grpc"

VMESS_UUID="0c890000-4733-b20e-067f-fc341bd20000"
VMESS_PATH_WS="%2FN4VMESS"
VMESS_WS_TAG="N4-VMess-WS"

# =================== Time (Start/End+5h only; no start message) ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
fmt(){ date -d @"$1" "+%Y-%m-%d %H:%M:%S %Z"; }
START_LOCAL="$(fmt "$START_EPOCH")"
END_LOCAL="$(fmt "$END_EPOCH")"

sec "Timing"
kv "Start:"      "${START_LOCAL}"
kv "End(+5h):"   "${END_LOCAL}"

# =================== Enable APIs & Deploy ===================
sec "Enable APIs"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet
ok "APIs Enabled"

sec "Deploying"
gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --timeout="$TIMEOUT" \
  --allow-unauthenticated \
  --port="$PORT" \
  --quiet
ok "Deployed Successfully"

# =================== Result ===================
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"

sec "Result"
ok "Service Ready"
kv "URL:" "${C_CYAN}${BOLD}${URL_CANONICAL}${RESET}"

# =================== Build Client URI ===================
make_vmess_ws_uri(){
  local host="$1"
  local json=$(cat <<JSON
{
  "v": "2",
  "ps": "${VMESS_WS_TAG}",
  "add": "m.googleapis.com",
  "port": "443",
  "id": "${VMESS_UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "${host}",
  "path": "/${VMESS_PATH_WS//%2F/}",
  "tls": "tls",
  "sni": "m.googleapis.com",
  "alpn": "http/1.1",
  "fp": "randomized"
}
JSON
)
  if base64 --help 2>&1 | grep -q '\-w'; then
    printf "vmess://%s" "$(printf '%s' "$json" | base64 -w0)"
  else
    printf "vmess://%s" "$(printf '%s' "$json" | base64 | tr -d '\n')"
  fi
}

URI=""
case "$PROTO" in
  trojan-grpc)
    URI="trojan://${TROJAN_PASS}@m.googleapis.com:443?mode=gun&security=tls&type=grpc&serviceName=${TROJAN_GRPC_SVC}&sni=${CANONICAL_HOST}#${TROJAN_GRPC_TAG}"
    ;;
  vless-ws)
    URI="vless://${VLESS_UUID}@m.googleapis.com:443?path=${VLESS_PATH_WS}&security=tls&alpn=http%2F1.1&encryption=none&host=${CANONICAL_HOST}&fp=randomized&type=ws&sni=m.googleapis.com#${VLESS_WS_TAG}"
    ;;
  vless-grpc)
    URI="vless://${VLESS_UUID_GRPC}@m.googleapis.com:443?mode=gun&security=tls&alpn=h2&encryption=none&type=grpc&serviceName=${VLESS_GRPC_SVC}&sni=${CANONICAL_HOST}#${VLESS_GRPC_TAG}"
    ;;
  vmess-ws)
    URI="$(make_vmess_ws_uri "${CANONICAL_HOST}")"
    ;;
esac

# =================== Notify (Deploy Success) ===================
tg_send "<b>✅ Deploy Success</b>
<b>🛎️ Service:</b> ${SERVICE}
<b>🧩 Protocol:</b> ${PROTO^^}
<b>🌍 Region:</b> ${REGION}
<b>🔗 URL:</b> ${URL_CANONICAL}
<b>🔑 Key:</b> <pre><code>${URI}</code></pre>
<b>🕒 Start:</b> ${START_LOCAL}
<b>⏳ End(+5h):</b> ${END_LOCAL}
<b>⏳ Validity:</b> 5 hours (End at: ${END_LOCAL})
"

printf "\n${C_GREEN}${BOLD}✨ Done. Prompts are bound to TTY; inline URL buttons (0–3) included; Start message removed.${RESET}\n"
