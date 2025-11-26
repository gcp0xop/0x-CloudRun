#!/usr/bin/env bash
set -euo pipefail

# =================== UI Colors ===================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
BOLD='\033[1m'

clear
printf "\n${RED}${BOLD}🚀 ALPHA${YELLOW}0x1${RESET}\n"
printf "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

# =================== 1. Setup ===================
if [[ -f .env ]]; then source ./.env; fi

if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then 
  printf "   ${CYAN}💎 Bot Token:${RESET} "
  read -r TELEGRAM_TOKEN
fi

if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then 
  printf "   ${CYAN}💎 Chat ID:${RESET}   "
  read -r TELEGRAM_CHAT_IDS
fi

# =================== 2. Region Check ===================
echo ""
echo -e "${YELLOW}➤ Checking Regions...${RESET}"

gcloud services enable run.googleapis.com --quiet >/dev/null 2>&1
REGIONS_LIST=$(gcloud run regions list --format="value(locationId)" 2>/dev/null || true)

if [[ -z "$REGIONS_LIST" ]]; then
    REGION="us-central1"
else
    # Simple auto-select UI
    echo "--------------------------------"
    i=1
    declare -a R_ARRAY
    for r in $REGIONS_LIST; do
        echo -e "   $i) ${WHITE}$r${RESET}"
        R_ARRAY[$i]=$r
        ((i++))
    done
    echo "--------------------------------"
    
    printf "   ${CYAN}➤ Select Region [Default: us-central1]:${RESET} "
    read -r SELECTION
    
    if [[ -n "$SELECTION" && -n "${R_ARRAY[$SELECTION]:-}" ]]; then
        REGION="${R_ARRAY[$SELECTION]}"
    else
        REGION="us-central1"
    fi
fi

echo -e "${BLUE}➤ Selected:${RESET} ${BOLD}${REGION}${RESET}"

# =================== 3. Configuration ===================
COUNT_FILE=".alpha_counter"
if [[ ! -f "$COUNT_FILE" ]]; then echo "0" > "$COUNT_FILE"; fi
CURRENT_COUNT=$(<"$COUNT_FILE")
NEXT_COUNT=$((CURRENT_COUNT + 1))
echo "$NEXT_COUNT" > "$COUNT_FILE"

SUFFIX=$(printf "%03d" "$NEXT_COUNT")
SERVER_NAME="Alpha0x1-${SUFFIX}"
GEN_UUID=$(cat /proc/sys/kernel/random/uuid)

SERVICE_NAME="alphas0x1"
IMAGE="a0x1/al0x1"
GRPC_SERVICE_NAME="Tg-@Alpha0x1"

# =================== 4. Deployment ===================
echo ""
echo -e "${YELLOW}➤ Deploying Server...${RESET}"

# Deploy with Full Power (Hidden Complexities)
gcloud run deploy "$SERVICE_NAME" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="4Gi" \
  --cpu="4" \
  --timeout="3600" \
  --allow-unauthenticated \
  --use-http2 \
  --no-cpu-throttling \
  --execution-environment=gen2 \
  --concurrency=1000 \
  --session-affinity \
  --ingress=all \
  --set-env-vars UUID="${GEN_UUID}",GOMAXPROCS="4",GOMEMLIMIT="3600MiB",GODEBUG="madvdontneed=1",TZ="Asia/Yangon" \
  --port="8080" \
  --min-instances=1 \
  --max-instances=2 \
  --quiet

echo -e "${YELLOW}➤ Optimizing Traffic...${RESET}"

# Force Traffic to Latest Revision (The Secret Sauce)
gcloud run services update-traffic "$SERVICE_NAME" \
  --to-latest \
  --region="$REGION" \
  --quiet >/dev/null 2>&1

# Get Domain & Warmup
URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}
curl -s -o /dev/null "https://${DOMAIN}"

# =================== 5. Notification ===================
echo -e "${YELLOW}➤ Sending Keys...${RESET}"

URI="vless://${GEN_UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${DOMAIN}#${SERVER_NAME}"

export TZ="Asia/Yangon"
START_LOCAL="$(date +'%d.%m.%Y %I:%M %p')"
END_LOCAL="$(date -d '+5 hours 10 minutes' +'%d.%m.%Y %I:%M %p')"

# Clean Message Format
MSG="<blockquote>🚀 ${SERVER_NAME} V2RAY SERVICE</blockquote>
<blockquote>🌍 Region: ${REGION}</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<pre><code>${URI}</code></pre>

<blockquote>✅ စတင်ချိန်: <code>${START_LOCAL}</code></blockquote>
<blockquote>⏳ပြီးဆုံးအချိန်: <code>${END_LOCAL}</code></blockquote>"

if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_IDS" ]]; then
  IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
  for chat_id in "${CHAT_ID_ARR[@]}"; do
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${chat_id}" \
      -d "parse_mode=HTML" \
      --data-urlencode "text=${MSG}" > /dev/null
    echo -e "${GREEN}✔ Sent to ID: ${chat_id}${RESET}"
  done
else
  printf "${RED}⚠ No Token found.${RESET}\n"
fi

# =================== Final Status ===================
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════╗${RESET}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Name" "${SERVER_NAME}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Region" "${REGION}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Specs" "4 vCPU / 4Gi RAM"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${GREEN}%-20s${RESET} ${YELLOW}║${RESET}\n" "Status" "Active ✅"
echo -e "${YELLOW}╚════════════════════════════════════════════╝${RESET}"
echo ""
