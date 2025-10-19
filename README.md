---

<h1 align="center">🚀 0x CloudRun</h1>
<h3 align="center">✨ Multi One-Click Deploy | Auto Telegram | 4 Protocols on CloudRun ✨</h3>
<p align="center">
  🇺🇲 <a href="README_EN.md">Read On English Language </a> </p>
---

## 📦 Overview

**0x CloudRun** သည် **Google Cloud Run** ပေါ်တွင်  
**VLESS / Trojan / VMess** Protocol မျိုးစုံကို  
တစ်ချက်တည်းဖြင့် **Auto Deploy** ပြုလုပ်ပေးသည့် Bash Script ဖြစ်ပါသည်။

> 🎯 **Qwiklabs Users** (Key ထုတ်မည့်သူများ) အတွက်အထူးသင့်တော်ပြီး  
> မိမိကိုယ်ပိုင် **GCP Account** တွင်လည်း အသုံးပြုနိုင်ပါသည်။

---

## 🧩 Features

- ⚙️ Auto Enable APIs — *(Cloud Run + Cloud Build)*  
- 🌍 Multi-Region Support — 🇺🇸 🇸🇬 🇹🇼 🇯🇵  
- 🧠 CPU / RAM Selector — *(1vCPU → 4vCPU)*  
- 🔗 Canonical Hostname Generator  
- ⏱️ Fixed Timeout (3600s) + 5-Hour Expiry Window  
- 📨 Telegram `<pre><code>` Output with **🚀 Keys Only**  
- 🧭 Paths (Server Config Compatible):
  - `grpc-0xcloudrun`
  - `/ws-0xcloudrun`
  - `trojan-0xgrpc`
  - `/0xvmess-ws`

---

## ⚡️ One-Click Command

**Cloud Shell** တွင် အောက်ပါ Script ကို Paste ပြီး Run လိုက်ပါ👇

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/0x/0x-CloudRun/main/0x.sh)
```
(or using wget)
```bash
bash <(wget -qO- https://raw.githubusercontent.com/0x/0x-CloudRun/main/0x.sh)
```

---

🤖 Telegram Integration (Optional)

Telegram Bot မှာ Result ကို Auto Receive လုပ်ချင်ပါက
အောက်ပါပုံစံအတိုင်း Token နှင့် Chat ID ကို Inline ထည့်ပါ👇
```bash
TELEGRAM_TOKEN="123456:ABC..." TELEGRAM_CHAT_ID="123456789" \
bash <(curl -fsSL https://raw.githubusercontent.com/gcp0xop/0x-CloudRun/main/0x.sh)

```
> သို့မဟုတ် Script Run ချိန်တွင် **Telegram Token** & **Chat ID** တောင်းလာလျှင်  
> တိကျစွာ စစ်ဆေးပြီး ထည့်ပါ။  
> 📩 **Bot ကို Start ထားမှသာ Result များကို Auto Send လုပ်ပါလိမ့်မည်။**

---

### 📤 Telegram Output Format

**Bot မှတဆင့် သင့် Telegram Account သို့**  
Deploy Info + 4 Protocol URLs (🚀) များကို  
**Copy-Ready `<pre><code>` Format** ဖြင့် ပေးပို့ပါလိမ့်မည်။

---

> 🧠 Example Output

>📦 **Service Info**  
>🏷️ Service : n4vpn  
>🗺️ Region  : 🇺🇸  Iowa (us-central1)  
>🧮 CPU/RAM : 2 vCPU / 4Gi
>🕒 Start   : 2025-10-11 01:30 AM  
>⏳ Expire  : 2025-10-11 06:30 AM  
>🔗 URL     : https://0xgcp-xxxxxxxx.us-central1.run.app  

>🚀 **VLESS gRPC**  
vless://UUID@...#N4%20VPN%20gRPC  

>🚀 **VLESS WS**  
vless://UUID@...#N4%20VPN%20WS  

>🚀 **TROJAN gRPC**  
trojan://pass@...#N4%20Trojan%20gRPC  

>🚀 **VMESS WS**  
vmess://base64...

---

### ❤️ Support & Join Telegram

🌐 [N4 VPN Official](https://t.me/n4vpn)  
💬 [N4 Community Group](https://t.me/n4vpnchat)  

⭐ **Star this repo if you love the project** —  
your support keeps the N4 ecosystem growing stronger!  

---

<p align="center">© 2025 N4 VPN — Built with 💙 for CloudRun Automation</p>
