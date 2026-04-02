#!/bin/bash
# Bandcamp → Warenkorb (ohne Login!)
# Liest URLs aus bandcamp.txt und fügt sie automatisch zum Warenkorb hinzu.
#
# Ausführen: Doppelklick auf bandcamp-cart.sh (Git Bash muss installiert sein)
#            oder: bash bandcamp-cart.sh

set -o pipefail

# Script-Verzeichnis ermitteln (funktioniert auch per Doppelklick)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_FILE="${SCRIPT_DIR}/bandcamp.txt"
COOKIE_FILE="${SCRIPT_DIR}/.bc_cookies.txt"

# --- Prüfen ob bandcamp.txt existiert ---
if [ ! -f "$LINK_FILE" ]; then
  echo "FEHLER: bandcamp.txt nicht gefunden!"
  echo "Erwartet: $LINK_FILE"
  echo ""
  echo "Lege eine Datei 'bandcamp.txt' neben das Script."
  echo "Eine Bandcamp-URL pro Zeile, z.B.:"
  echo "  https://artist.bandcamp.com/track/song-name"
  echo "  https://artist.bandcamp.com/album/album-name"
  echo ""
  read -p "Enter zum Beenden..."
  exit 1
fi

# --- URLs aus Datei lesen (Kommentare und Leerzeilen ignorieren) ---
URLS=()
while IFS= read -r line; do
  line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$line" ] && continue
  [[ "$line" == \#* ]] && continue
  URLS+=("$line")
done < "$LINK_FILE"

if [ ${#URLS[@]} -eq 0 ]; then
  echo "FEHLER: Keine URLs in bandcamp.txt gefunden!"
  echo ""
  echo "Füge Bandcamp-Links ein, eine pro Zeile."
  echo ""
  read -p "Enter zum Beenden..."
  exit 1
fi

# --- Warenkorb leeren für neuen Durchlauf ---
> "$COOKIE_FILE"

SUCCESS=0
FAIL=0
SYNC=1
CART_LEN=0

echo "=========================================="
echo "  Bandcamp → Warenkorb (automatisch)"
echo "=========================================="
echo "Quelle: bandcamp.txt"
echo "Titel:  ${#URLS[@]}"
echo ""

for i in "${!URLS[@]}"; do
  num=$((i + 1))
  url="${URLS[$i]}"
  label=$(echo "$url" | sed 's|.*/||')
  echo -n "[$num/${#URLS[@]}] $label ... "

  # --- Subdomain (Artist) aus URL extrahieren ---
  artist_sub=$(echo "$url" | sed -n 's|https://\([^.]*\)\.bandcamp\.com.*|\1|p')
  if [ -z "$artist_sub" ]; then
    echo "FEHLER (ungültige URL)"
    FAIL=$((FAIL + 1))
    continue
  fi
  cart_url="https://${artist_sub}.bandcamp.com/cart/cb"

  # --- Seite laden & item_id extrahieren ---
  page=$(curl -sL -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
    "$url" 2>/dev/null)

  if [ -z "$page" ]; then
    echo "FEHLER (Seite nicht ladbar)"
    FAIL=$((FAIL + 1))
    sleep 1
    continue
  fi

  # item_id aus HTML extrahieren (diverse Formate versuchen)
  item_id=$(echo "$page" | grep -o 'item_id&quot;:[0-9]*' | head -1 | sed 's/.*://')
  if [ -z "$item_id" ]; then
    item_id=$(echo "$page" | grep -o 'item_id":[0-9]*' | head -1 | sed 's/.*://')
  fi
  if [ -z "$item_id" ]; then
    item_id=$(echo "$page" | grep -o 'data-item-id="[0-9]*"' | head -1 | sed 's/.*="//;s/"//')
  fi

  if [ -z "$item_id" ]; then
    echo "FEHLER (item_id nicht gefunden)"
    FAIL=$((FAIL + 1))
    sleep 1
    continue
  fi

  # --- Item-Typ bestimmen ---
  case "$url" in
    */album/*) item_type="a" ;;
    *)         item_type="t" ;;
  esac

  # --- Zum Warenkorb hinzufügen ---
  local_id="lc$(date +%s)${num}"
  response=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Origin: https://${artist_sub}.bandcamp.com" \
    -H "Referer: $url" \
    -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
    -d "req=add&item_type=${item_type}&item_id=${item_id}&unit_price=0&quantity=1&local_id=${local_id}&sync_num=${SYNC}&cart_length=${CART_LEN}" \
    "$cart_url" 2>/dev/null)

  # --- Antwort prüfen ---
  if echo "$response" | grep -q '"id":'; then
    cart_id=$(echo "$response" | grep -o '"id":[0-9]*' | head -1 | sed 's/.*://')
    echo "OK (Cart-ID: $cart_id)"
    SUCCESS=$((SUCCESS + 1))
    SYNC=$((SYNC + 1))
    CART_LEN=$((CART_LEN + 1))
  elif echo "$response" | grep -q '"error":true'; then
    msg=$(echo "$response" | grep -o '"error_message":"[^"]*"' | sed 's/.*://;s/"//g')
    echo "FEHLER ($msg)"
    FAIL=$((FAIL + 1))
  else
    echo "UNBEKANNT"
    FAIL=$((FAIL + 1))
  fi

  sleep 1
done

echo ""
echo "=========================================="
echo "  Ergebnis: $SUCCESS OK / $FAIL Fehler"
echo "=========================================="

if [ $SUCCESS -gt 0 ]; then
  echo ""
  echo "Öffne Warenkorb zum Bezahlen..."
  start "https://bandcamp.com/cart" 2>/dev/null || \
    echo ">> Manuell öffnen: https://bandcamp.com/cart"
fi

echo ""
read -p "Enter zum Beenden..."
