#!/bin/bash
# Bandcamp → Warenkorb
# Öffnet alle Bandcamp-URLs im Browser. Klick auf "Buy" auf jeder Seite.
#
# Ausführen: Doppelklick oder bash bandcamp-cart.sh

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_FILE="${SCRIPT_DIR}/bandcamp.txt"

# --- Prüfen ob bandcamp.txt existiert ---
if [ ! -f "$LINK_FILE" ]; then
  echo "FEHLER: bandcamp.txt nicht gefunden!"
  echo "Erwartet: $LINK_FILE"
  echo ""
  read -p "Enter zum Beenden..."
  exit 1
fi

# --- URLs aus Datei lesen ---
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
  read -p "Enter zum Beenden..."
  exit 1
fi

echo "=========================================="
echo "  Bandcamp → Browser öffnen"
echo "=========================================="
echo "Quelle: bandcamp.txt"
echo "Titel:  ${#URLS[@]}"
echo ""

for i in "${!URLS[@]}"; do
  num=$((i + 1))
  url="${URLS[$i]}"
  label=$(echo "$url" | sed 's|.*/||')
  echo "[$num/${#URLS[@]}] $label"
  start "$url" 2>/dev/null || xdg-open "$url" 2>/dev/null
  sleep 2
done

echo ""
echo "=========================================="
echo "  Fertig!"
echo "=========================================="
echo ""
echo "Auf jeder Seite auf 'Buy' klicken."
echo "Danach alles auf einmal bezahlen."
echo ""
read -p "Enter zum Beenden..."
