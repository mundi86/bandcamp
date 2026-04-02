#!/bin/bash
# Bandcamp Auto-Cart (Reliable Parallel Edition)
# Benötigt: Chrome + Node.js (v22+)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_FILE="${SCRIPT_DIR}/bandcamp.txt"
DEBUG_PORT=9222
TMP_JS="${TEMP:-/tmp}/bc_helper_$(date +%s).js"
CONCURRENCY=5

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
const concurrency = parseInt(process.argv[4] || "5");

function httpGet(url) {
  return new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${port}/json/version`, res => {
      let data = ""; res.on("data", c => data += c); res.on("end", () => resolve(JSON.parse(data)));
    }).on("error", reject);
  });
}

async function main() {
  const ver = await httpGet();
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

  // 1. Keep-Alive Tab erstellen (damit Chrome nicht schließt)
  const mainTab = await send("Target.createTarget", { url: "about:blank" });
  const mainTid = mainTab.result.targetId;

  let index = 0;
  let success = 0, fail = 0;

  async function processNext() {
    if (index >= urls.length) return;
    const i = index++;
    const url = urls[i].trim();
    const num = i + 1;
    const label = url.split("/").pop();

    try {
      const cr = await send("Target.createTarget", { url: "about:blank" });
      const tid = cr.result.targetId;
      const ar = await send("Target.attachToTarget", { targetId: tid, flatten: true });
      const sid = ar.result.sessionId;
      await send("Runtime.enable", {}, sid);
      await send("Page.navigate", { url }, sid);

      let val = "TIMEOUT";
      for (let t = 0; t < 25; t++) {
        await sleep(800);
        const r = await send("Runtime.evaluate", {
          expression: `(async () => {
            const h = document.documentElement.innerHTML;
            const m = h.match(/\"item_id\":\\s*(\\d+)/) || h.match(/data-item-id=\"(\\d+)\"/) || h.match(/item[-_]id.{0,10}?(\\d{5,})/);
            if (!m) return null;
            const res = await fetch(window.location.origin + '/cart/cb', {
              method: 'POST',
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: 'req=add&item_type=' + (window.location.href.includes('/album/') ? 'a' : 't') + '&item_id=' + m[1] + '&unit_price=0&quantity=1&local_id=lc' + Date.now() + '&sync_num=${num}&cart_length=0'
            });
            const data = await res.json();
            return data.id ? 'OK' : 'ERR:' + JSON.stringify(data);
          })()`,
          awaitPromise: true, returnByValue: true
        }, sid);
        if (r.result?.result?.value) { val = r.result.result.value; break; }
      }

      if (val === "OK") { console.log("["+num+"/"+urls.length+"] " + label + " ... OK"); success++; }
      else { console.log("["+num+"/"+urls.length+"] " + label + " ... FEHLER (" + val + ")"); fail++; }
      await send("Target.closeTarget", { targetId: tid });
    } catch (e) { fail++; }
  }

  const workers = Array(Math.min(concurrency, urls.length)).fill(0).map(async () => {
    while (index < urls.length) await processNext();
  });
  await Promise.all(workers);

  console.log("\nErgebnis: " + success + " OK / " + fail + " Fehler");
  
  if (success > 0) {
    console.log("\nÖffne Warenkorb...");
    const ar = await send("Target.attachToTarget", { targetId: mainTid, flatten: true });
    await send("Page.navigate", { url: "https://bandcamp.com/cart" }, ar.result.sessionId);
  } else {
    // Falls nichts im Korb ist, können wir den Keep-Alive Tab schließen
    await send("Target.closeTarget", { targetId: mainTid });
  }
}
main().catch(e => { console.error(e); process.exit(1); });
NODEEOF

# --- START ---
echo "=========================================="
echo "  Bandcamp -> Warenkorb (Parallel v2.1)"
echo "=========================================="

if ! curl -s "http://127.0.0.1:9222/json/version" &>/dev/null; then
  "$CHROME" --remote-debugging-port=9222 --user-data-dir="${TEMP:-/tmp}/bc-cart-profile" &>/dev/null &
  sleep 3
fi

URLS_JSON="["$(printf '"%s",' "${URLS[@]}" | sed 's/,$//')"]"
node "$TMP_JS" "9222" "$URLS_JSON" "$CONCURRENCY"
rm -f "$TMP_JS"
echo ""
read -p "Fertig. Enter zum Beenden..."
