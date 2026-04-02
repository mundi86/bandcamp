#!/bin/bash
# Bandcamp Auto-Cart (Reliable Turbo Edition)
# Benötigt: Chrome + Node.js (v22+)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_FILE="${SCRIPT_DIR}/bandcamp.txt"
DEBUG_PORT=9222
TMP_JS="${TEMP:-/tmp}/bc_helper_$(date +%s).js"

# --- URLs laden ---
[ ! -f "$LINK_FILE" ] && { echo "FEHLER: bandcamp.txt fehlt!"; exit 1; }
URLS=()
while IFS= read -r line; do
  line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$line" ] || [[ "$line" == \#* ]] || URLS+=("$line")
done < "$LINK_FILE"
[ ${#URLS[@]} -eq 0 ] && { echo "FEHLER: Keine URLs!"; exit 1; }

# --- Node.js & Chrome finden ---
command -v node &>/dev/null || { echo "FEHLER: Node.js fehlt!"; exit 1; }
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
[ ! -f "$CHROME" ] && CHROME="$LOCALAPPDATA/Google/Chrome/Application/chrome.exe"
[ ! -f "$CHROME" ] && CHROME=$(command -v google-chrome || command -v chromium)

# --- Node.js CDP Helper ---
cat << 'NODEEOF' > "$TMP_JS"
const WebSocket = global.WebSocket || (typeof WebSocket !== "undefined" ? WebSocket : null);
const http = require("http");
const port = process.argv[2] || 9222;
const urls = JSON.parse(process.argv[3] || "[]");

async function main() {
  const ver = await new Promise((res, rej) => {
    http.get(`http://127.0.0.1:${port}/json/version`, r => {
      let d = ""; r.on("data", c => d += c); r.on("end", () => res(JSON.parse(d)));
    }).on("error", rej);
  });
  
  const ws = new WebSocket(ver.webSocketDebuggerUrl);
  let msgId = 100;
  const pending = {};
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending[m.id]) { pending[m.id](m); delete pending[m.id]; }
  };
  const send = (method, params = {}, sessionId = null) => new Promise(r => {
    const id = ++msgId;
    const msg = { id, method, params };
    if (sessionId) msg.sessionId = sessionId;
    pending[id] = r;
    ws.send(JSON.stringify(msg));
  });
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  await new Promise(r => { ws.onopen = r; });

  let success = 0, fail = 0;
  // Wir nutzen einen persistenten Tab für alle Navigationsvorgänge
  const cr = await send("Target.createTarget", { url: "about:blank" });
  const tid = cr.result.targetId;
  const ar = await send("Target.attachToTarget", { targetId: tid, flatten: true });
  const sid = ar.result.sessionId;
  await send("Runtime.enable", {}, sid);

  for (let i = 0; i < urls.length; i++) {
    const url = urls[i].trim();
    const num = i + 1;
    const label = url.split("/").pop();
    process.stdout.write(`[${num}/${urls.length}] ${label} ... `);

    await send("Page.navigate", { url }, sid);
    
    let result = "TIMEOUT";
    for (let t = 0; t < 40; t++) { // Max 20 Sek.
      await sleep(500);
      const r = await send("Runtime.evaluate", {
        expression: `(async () => {
          try {
            if (!document.body) return null;
            
            // ID Suche
            let id = null;
            if (window.TralbumData && window.TralbumData.id) id = window.TralbumData.id;
            if (!id) {
               const m = document.documentElement.innerHTML.match(/\"item_id\":\\s*(\\d+)/) || 
                         document.documentElement.innerHTML.match(/data-item-id=\"(\\d+)\"/) ||
                         document.documentElement.innerHTML.match(/item[-_]id.{0,10}?(\\d{5,})/);
               if (m) id = m[1];
            }
            if (!id) return null;
            
            const type = window.location.href.includes('/album/') ? 'a' : 't';
            const res = await fetch(window.location.origin + '/cart/cb', {
              method: 'POST',
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: 'req=add&item_type=' + type + '&item_id=' + id + '&quantity=1&local_id=lc'+Date.now()
            });
            const data = await res.json();
            return data.id ? 'OK' : 'ERR:' + (data.error_message || JSON.stringify(data));
          } catch(e) { return 'ERR:' + e.message; }
        })()`,
        awaitPromise: true, returnByValue: true
      }, sid);
      
      const val = r.result?.result?.value;
      if (val) { result = val; break; }
    }

    if (result === "OK") { console.log("OK"); success++; }
    else { console.log("FEHLER (" + result + ")"); fail++; }
  }

  console.log(`\n==========================================`);
  console.log(`  Ergebnis: ${success} OK / ${fail} Fehler`);
  console.log(`==========================================\n`);
  
  if (success > 0) {
    console.log("Öffne Warenkorb...");
    await send("Page.navigate", { url: "https://bandcamp.com/cart" }, sid);
    await sleep(2000);
  }
}
main().catch(e => { console.error(e); process.exit(1); });
NODEEOF

# --- START ---
echo "=========================================="
echo "  Bandcamp -> Warenkorb (Turbo Mode)"
echo "=========================================="

# Sicherstellen, dass Chrome läuft
if ! curl -s "http://127.0.0.1:9222/json/version" &>/dev/null; then
  echo "Starte Chrome..."
  "$CHROME" --remote-debugging-port=9222 --user-data-dir="${TEMP:-/tmp}/bc-cart-profile" --no-first-run --no-default-browser-check &>/dev/null &
  sleep 3
fi

URLS_JSON="["$(printf '"%s",' "${URLS[@]}" | sed 's/,$//')"]"
node "$TMP_JS" "9222" "$URLS_JSON"
rm -f "$TMP_JS"

echo ""
echo "Script beendet. Browser bleibt für Checkout offen."
read -p "Enter zum Beenden des Scripts..."
