#!/bin/bash
# Bandcamp Auto-Cart (Fast Parallel Version)
# BenÃ¶tigt: Chrome + Node.js (v22+)
#
# AusfÃ¼hren: bash bandcamp-cart.sh

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_FILE="${SCRIPT_DIR}/bandcamp.txt"
DEBUG_PORT=9222
TMP_JS="${TEMP:-/tmp}/bc_helper_$(date +%s).js"
CONCURRENCY=5

# --- URLs laden ---
if [ ! -f "$LINK_FILE" ]; then
  echo "FEHLER: bandcamp.txt nicht gefunden!"
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
  echo "FEHLER: Keine URLs in bandcamp.txt!"
  read -p "Enter zum Beenden..."; exit 1
fi

# --- Node.js prÃ¼fen ---
if ! command -v node &>/dev/null; then
  echo "FEHLER: Node.js ist nicht installiert!"
  read -p "Enter zum Beenden..."; exit 1
fi

# --- Chrome finden ---
CHROME=""
if [[ "$OSTYPE" == "darwin"* ]]; then
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  CHROME=$(command -v google-chrome 2>/dev/null || command -v google-chrome-stable 2>/dev/null || command -v chromium-browser 2>/dev/null || command -v chromium 2>/dev/null)
else
  CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
  [ ! -f "$CHROME" ] && CHROME="$LOCALAPPDATA/Google/Chrome/Application/chrome.exe"
fi

if [ -z "$CHROME" ] || [ ! -f "$CHROME" ]; then
  echo "FEHLER: Chrome nicht gefunden!"
  read -p "Enter zum Beenden..."; exit 1
fi

# --- Node.js CDP Helper ---
cat << 'NODEEOF' > "$TMP_JS"
const WebSocket = global.WebSocket || (typeof WebSocket !== "undefined" ? WebSocket : null);
const http = require("http");

const port = process.argv[2] || 9222;
const urls = JSON.parse(process.argv[3] || "[]");
const concurrency = parseInt(process.argv[4] || "3");

function httpGet(url) {
  return new Promise((resolve, reject) => {
    http.get(url, res => {
      let data = "";
      res.on("data", c => data += c);
      res.on("end", () => resolve(JSON.parse(data)));
    }).on("error", reject);
  });
}

async function main() {
  const ver = await httpGet(`http://127.0.0.1:${port}/json/version`);
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
  let active = 0;
  let index = 0;

  async function processNext() {
    if (index >= urls.length) return;
    const i = index++;
    const url = urls[i].trim();
    const num = i + 1;
    const label = url.split("/").pop();

    try {
      // Tab erstellen & Attach
      const cr = await send("Target.createTarget", { url: "about:blank" });
      const targetId = cr.result.targetId;
      const ar = await send("Target.attachToTarget", { targetId, flatten: true });
      const sid = ar.result.sessionId;

      await send("Runtime.enable", {}, sid);
      await send("Page.navigate", { url }, sid);

      // Dynamisch auf item_id warten (max 10s)
      let val = "ERR:timeout";
      for (let t = 0; t < 20; t++) {
        await sleep(500);
        const r = await send("Runtime.evaluate", {
          expression: `(async () => {
            const m = document.documentElement.innerHTML.match(/item[-_]id.{0,10}?(\\d{5,})/);
            if (!m) return null;
            const r = await fetch(window.location.origin + '/cart/cb', {
              method: 'POST',
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: 'req=add&item_type=' + (window.location.href.includes('/album/') ? 'a' : 't') + '&item_id=' + m[1] + '&unit_price=0&quantity=1&local_id=lc'+Date.now()+'&sync_num=${num}&cart_length=0'
            });
            const d = await r.json();
            return d.id ? 'OK:' + d.id : 'ERR:' + (d.error_message || 'unknown');
          })()`,
          awaitPromise: true,
          returnByValue: true
        }, sid);
        
        const res = r.result?.result?.value;
        if (res) { val = res; break; }
      }

      if (val.startsWith("OK:")) {
        console.log(`[${num}/${urls.length}] ${label} ... OK`);
        success++;
      } else {
        console.log(`[${num}/${urls.length}] ${label} ... FEHLER (${val})`);
        fail++;
      }

      await send("Target.closeTarget", { targetId });
    } catch (e) {
      console.log(`[${num}/${urls.length}] ${label} ... CRASH (${e.message})`);
      fail++;
    }
  }

  const workers = Array(Math.min(concurrency, urls.length)).fill(0).map(async () => {
    while (index < urls.length) await processNext();
  });

  await Promise.all(workers);

  console.log(`\n==========================================`);
  console.log(`  Ergebnis: ${success} OK / ${fail} Fehler`);
  console.log(`==========================================\n`);

  if (success > 0) {
    const cr = await send("Target.createTarget", { url: "https://bandcamp.com/cart" });
  }
}

main().catch(e => { console.error(e); process.exit(1); });
NODEEOF

# ==========================================
#   START
# ==========================================
echo "=========================================="
echo "  Bandcamp -> Warenkorb (FAST & PARALLEL)"
echo "=========================================="
echo "Quelle: bandcamp.txt"
echo "Titel:  ${#URLS[@]}"
echo "Worker: $CONCURRENCY"
echo ""

if ! curl -s "http://127.0.0.1:${DEBUG_PORT}/json/version" &>/dev/null; then
  "$CHROME" --remote-debugging-port=$DEBUG_PORT --user-data-dir="${TEMP:-/tmp}/bc-cart-profile" &>/dev/null &
  echo -n "Starte Chrome..."
  READY=0
  for i in $(seq 1 30); do
    sleep 0.5
    if curl -s "http://127.0.0.1:${DEBUG_PORT}/json/version" &>/dev/null; then
      READY=1; break
    fi
  done
  [ $READY -eq 0 ] && { echo " FEHLER"; rm -f "$TMP_JS"; exit 1; }
  echo " OK"
fi

URLS_JSON="["$(printf '"%s",' "${URLS[@]}" | sed 's/,$//')"]"
node "$TMP_JS" "$DEBUG_PORT" "$URLS_JSON" "$CONCURRENCY"
rm -f "$TMP_JS"

echo ""
read -p "Enter zum Beenden..."

