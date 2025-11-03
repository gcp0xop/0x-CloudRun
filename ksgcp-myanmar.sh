#!/bin/bash
# KSGCP Myanmar Optimized - Best 3 Regions
# Usage: ./ksgcp-myanmar.sh

set -euo pipefail

# ===== Colors =====
if [[ -t 1 ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'
  C_CYAN=$'\e[38;5;44m'; C_GREEN=$'\e[38;5;46m'
  C_YEL=$'\e[38;5;226m'; C_ORG=$'\e[38;5;214m'
else
  RESET= BOLD= C_CYAN= C_GREEN= C_YEL= C_ORG=
fi

echo "\n${C_CYAN}${BOLD}🇲🇲 KSGCP Myanmar Optimized Deployment${RESET}"
echo "${C_CYAN}=============================================${RESET}"

# ===== Myanmar Best 3 Regions =====
REGIONS=("us-west1" "us-west2" "us-west3")
REGION_NAMES=("Oregon" "Los Angeles" "Salt Lake")
KEYS=()

for i in "${!REGIONS[@]}"; do
  region="${REGIONS[$i]}"
  name="${REGION_NAMES[$i]}"
  
  echo "\n${C_YEL}🚀 Deploying: ${name} (${region})${RESET}"
  
  gcloud run deploy "ksgcp-${region}" \
    --image=docker.io/n4pro/tr:latest \
    --region="${region}" \
    --cpu=8 --memory=16Gi \
    --allow-unauthenticated \
    --min-instances=1 \
    --quiet

  URL=$(gcloud run services describe "ksgcp-${region}" --format='value(status.url)')
  HOST="${URL#https://}"
  KEY="trojan://Trojan-2025@vpn.googleapis.com:443?path=%2FN4&security=tls&host=${HOST}&type=ws#KSGCP-${name}"
  KEYS+=("$KEY")
  
  echo "${C_GREEN}✅ ${name}: Ready${RESET}"
  echo "   ${C_ORG}${KEY}${RESET}"
done

# ===== Telegram Notification =====
if [[ -n "${TELEGRAM_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "\n${C_CYAN}📱 Sending to Telegram...${RESET}"
  
  MESSAGE="🇲🇲 <b>KSGCP Myanmar Optimized</b> (Best 3 Regions)

🏆 <b>Oregon</b> - Fastest for Myanmar
<code>${KEYS[0]}</code>

🥈 <b>Los Angeles</b> - Good Backup  
<code>${KEYS[1]}</code>

🥉 <b>Salt Lake</b> - Average
<code>${KEYS[2]}</code>

<b>Usage Tip:</b> Use Oregon server first for best speed!"

  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MESSAGE}" \
    -d "parse_mode=HTML" \
    > /dev/null
  
  echo "${C_GREEN}✅ Telegram notification sent!${RESET}"
fi

echo "\n${C_GREEN}${BOLD}🎯 All done! Myanmar-optimized KSGCP servers are ready.${RESET}"
echo "${C_CYAN}⭐ Recommendation: Use Oregon server for best performance from Myanmar${RESET}"
