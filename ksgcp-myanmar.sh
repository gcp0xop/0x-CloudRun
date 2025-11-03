#!/bin/bash
# Myanmar optimized all-in-one script

echo "🇲🇲 KSGCP Myanmar Optimized Deployment"
echo "======================================"

# Deploy to 3 best regions
REGIONS=("us-west1" "us-west2" "us-west3")
REGION_NAMES=("Oregon" "Los Angeles" "Salt Lake")
KEYS=()

for i in "${!REGIONS[@]}"; do
  echo "🚀 Deploying: ${REGION_NAMES[$i]}"
  
  gcloud run deploy "ksgcp-${REGIONS[$i]}" \
    --image=docker.io/n4pro/tr:latest \
    --region="${REGIONS[$i]}" \
    --cpu=8 --memory=16Gi \
    --quiet

  URL=$(gcloud run services describe "ksgcp-${REGIONS[$i]}" --format='value(status.url)')
  HOST="${URL#https://}"
  KEY="trojan://Trojan-2025@vpn.googleapis.com:443?path=%2FN4&security=tls&host=${HOST}&type=ws#KSGCP-${REGION_NAMES[$i]}"
  KEYS+=("$KEY")
  
  echo "✅ ${REGION_NAMES[$i]}: Ready"
done

# Send to Telegram
MESSAGE="🇲🇲 KSGCP Myanmar-Optimized (Best 3):\n\n1. 🏆 Oregon\n${KEYS[0]}\n\n2. 🥈 Los Angeles\n${KEYS[1]}\n\n3. 🥉 Salt Lake\n${KEYS[2]}"

curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
  -d "chat_id=$CHAT_ID" \
  -d "text=$MESSAGE" \
  -d "parse_mode=HTML"

echo "🎯 All done! Check Telegram for keys."
