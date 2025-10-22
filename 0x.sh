#!/usr/bin/env bash
set -euo pipefail

# ... (UI/banner/function definitions remain unchanged)

# =================== Telegram Notify ===================
banner "📣 Step 10 — Telegram Notify"

MSG=$(cat <<EOF
✅ <b>CloudRun Deploy Success</b>
━━━━━━━━━━━━━━━━━━
<blockquote>🌍 <b>Region:</b> ${REGION}
⚙️ <b>Protocol:</b> ${PROTO^^}
🔗 <b>URL:</b> <a href="${URL_CANONICAL}">${URL_CANONICAL}</a></blockquote>
🔑 <b>V2Ray Configuration Access Key :</b>
<pre><code>${URI}</code></pre>
<blockquote>🕒 <b>Start:</b> ${START_LOCAL}
⏳ <b>End:</b> ${END_LOCAL}</blockquote>
━━━━━━━━━━━━━━━━━━
EOF
)

tg_send "${MSG}"

printf "\n${C_GREEN}${BOLD}✨ Done — Warm Instance Enabled (min=1) | Beautiful Banner UI | Cold Start Prevented${RESET}\n"
printf "${C_GREY}📄 Log file: ${LOG_FILE}${RESET}\n"
