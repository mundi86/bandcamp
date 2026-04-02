#!/bin/bash
# Bandcamp Auto-Cart (Bash + Chrome — kein Python nötig!)
# Startet Chrome mit Remote Debugging und fügt alles per JavaScript im Browser hinzu.
#
# Mac: bash bandcamp-cart.sh
# Linux: bash bandcamp-cart.sh
# Windows (Git Bash): bash bandcamp-cart.sh

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_FILE="${SCRIPT_DIR}/bandcamp.txt"
DEBUG_PORT=9222

# --- URLs laden ---
if [ ! -f "$LINK_FILE" ]; then
  echo "FEHLER: bandcamp.txt nicht gefunden!"
  echo "Erwartet: $LINK_FILE"
  read -p "Enter zum Beenden..."; exit 1
fi

URLS=()
while IFS= read -r line; do
  line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$line" ] && continue
  [[ "$line" == \#* ]] && continue
  URLS+=("$line")
done < "$LINK_FILE"

if [ ${#URLS[@]} -eq 0 ]; then
  echo "FEHLER: Keine URLs in bandcamp.txt gefunden!"
  read -p "Enter zum Beenden..."; exit 1
fi

# --- Chrome finden ---
CHROME=""
if [[ "$OSTYPE" == "darwin"* ]]; then
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ ! -f "$CHROME" ] && CHROME=""
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  CHROME=$(command -v google-chrome 2>/dev/null || command -v google-chrome-stable 2>/dev/null || command -v chromium-browser 2>/dev/null || command -v chromium 2>/dev/null)
else
  # Windows (Git Bash)
  CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
  [ ! -f "$CHROME" ] && CHROME="/c/Program Files (x86)/Google/Chrome/Application/chrome.exe"
  [ ! -f "$CHROME" ] && CHROME="$LOCALAPPDATA/Google/Chrome/Application/chrome.exe"
fi

if [ -z "$CHROME" ] || [ ! -f "$CHROME" ]; then
  echo "FEHLER: Chrome nicht gefunden!"
  echo "Bitte Chrome installieren: https://www.google.com/chrome/"
  read -p "Enter zum Beenden..."; exit 1
fi

# --- Funktionen ---
cdp_eval() {
  local expr="$1"
  local encoded
  encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$expr'''))" 2>/dev/null || \
            node -e "console.log(encodeURIComponent(process.argv[1]))" "$expr" 2>/dev/null)
  if [ -z "$encoded" ]; then
    # Fallback: crude URL encoding
    encoded=$(echo "$expr" | sed 's/ /%20/g; s/"/%22/g; s/#/%23/g; s/+/%2B/g')
  fi
  curl -s -X PUT "http://127.0.0.1:${DEBUG_PORT}/json/evaluate?expression=${encoded}" 2>/dev/null
}

cdp_eval_value() {
  local result
  result=$(cdp_eval "$1")
  echo "$result" | grep -o '"result".*"value":"[^"]*"' | sed 's/.*"value":"//;s/"$//' || echo ""
}

# --- Chrome mit DevTools starten ---
echo "=========================================="
echo "  Bandcamp → Warenkorb (automatisch)"
echo "=========================================="
echo "Quelle: bandcamp.txt"
echo "Titel:  ${#URLS[@]}"
echo ""

"$CHROME" --remote-debugging-port=$DEBUG_PORT --user-data-dir="/tmp/bc-cart-profile" &>/dev/null &
CHROME_PID=$!

echo -n "Warte auf Chrome..."
READY=0
for i in $(seq 1 20); do
  sleep 0.5
  if curl -s "http://127.0.0.1:${DEBUG_PORT}/json/version" &>/dev/null; then
    READY=1
    break
  fi
done

if [ $READY -eq 0 ]; then
  echo " FEHLER"
  echo "Konnte Chrome DevTools nicht erreichen."
  kill $CHROME_PID 2>/dev/null
  read -p "Enter zum Beenden..."; exit 1
fi
echo " OK"
echo ""

# --- Items hinzufügen ---
SUCCESS=0
FAIL=0

for i in "${!URLS[@]}"; do
  num=$((i + 1))
  url="${URLS[$i]}"
  label=$(echo "$url" | sed 's|.*/||')
  echo -n "[$num/${#URLS[@]}] $label ... "

  # URL laden
  encoded_url=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$url'))" 2>/dev/null || \
                 node -e "console.log(encodeURIComponent(process.argv[1]))" "$url" 2>/dev/null)
  curl -s -X PUT "http://127.0.0.1:${DEBUG_PORT}/json/new?${encoded_url}" &>/dev/null
  sleep 4

  # Item-Typ
  case "$url" in
    */album/*) item_type="a" ;;
    *)         item_type="t" ;;
  esac

  # JavaScript im Browser: Seite laden, item_id extrahieren, zum Warenkorb hinzufügen
  js="(async function(){try{var p=await fetch('${url}');var h=await p.text();var m=h.match(/item_id.{0,5}?(\\d{5,})/);if(!m)return'ERR:no_item_id';var id=m[1];var r=await fetch(window.location.origin+'/cart/cb',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'req=add&item_type=${item_type}&item_id='+id+'&unit_price=0&quantity=1&local_id=lc${num}&sync_num=${num}&cart_length=$((num-1))'});var d=await r.json();return d.id?'OK:'+d.id:'ERR:'+(d.error_message||'unknown')}catch(e){return'ERR:'+e.message}})()"

  result=$(cdp_eval_value "$js")

  case "$result" in
    OK:*)
      cart_id=$(echo "$result" | sed 's/OK://')
      echo "OK (Cart-ID: $cart_id)"
      SUCCESS=$((SUCCESS + 1))
      ;;
    ERR:*)
      msg=$(echo "$result" | sed 's/ERR://')
      echo "FEHLER ($msg)"
      FAIL=$((FAIL + 1))
      ;;
    *)
      echo "UNBEKANNT"
      FAIL=$((FAIL + 1))
      ;;
  esac

  sleep 1
done

# --- Ergebnis ---
echo ""
echo "=========================================="
echo "  Ergebnis: $SUCCESS OK / $FAIL Fehler"
echo "=========================================="

if [ $SUCCESS -gt 0 ]; then
  echo ""
  echo "Öffne Warenkorb zum Bezahlen..."
  cart_encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('https://bandcamp.com/cart'))" 2>/dev/null || \
                 node -e "console.log(encodeURIComponent('https://bandcamp.com/cart'))" 2>/dev/null)
  curl -s -X PUT "http://127.0.0.1:${DEBUG_PORT}/json/new?${cart_encoded}" &>/dev/null
fi

echo ""
echo "Browser offen lassen → Checkout klicken!"
echo ""
read -p "Enter zum Beenden..."
