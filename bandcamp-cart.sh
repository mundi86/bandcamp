#!/bin/bash
# Bandcamp Auto-Cart (Perfect Price Edition)
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

function httpGet(url) {
  return new Promise((resolve, reject) => {
    http.get(url, res => {
      let data = ""; res.on("data", c => data += c); res.on("end", () => resolve(JSON.parse(data)));
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

  // 1. Anker Tab suchen
  const targets = await httpGet(`http://127.0.0.1:${port}/json/list`);
  const mainTid = targets[0].id;

  let success = 0, fail = 0;
  let cartCount = 0;

  for (let i = 0; i < urls.length; i++) {
    const url = urls[i].trim();
    const num = i + 1;
    const label = url.split("/").pop();
    process.stdout.write(`[${num}/${urls.length}] ${label} ... `);

    try {
      const cr = await send("Target.createTarget", { url: "about:blank" });
      const tid = cr.result.targetId;
      const ar = await send("Target.attachToTarget", { targetId: tid, flatten: true });
      const sid = ar.result.sessionId;
      await send("Runtime.enable", {}, sid);
      await send("Page.navigate", { url }, sid);

      let val = "TIMEOUT";
      let priceInfo = "0.00";
      for (let t = 0; t < 25; t++) {
        await sleep(1000);
        const r = await send("Runtime.evaluate", {
          expression: `(async () => {
            try {
              const getPrice = () => {
                if (window.TralbumData) {
                  const td = window.TralbumData;
                  if (td.current && td.current.minimum_price != null) return td.current.minimum_price;
                  if (td.minimum_price_nonzero != null) return td.minimum_price_nonzero;
                  if (td.minimum_price != null) return td.minimum_price;
                  if (td.current && td.current.price != null) return td.current.price;
                }
                const el = document.querySelector('[data-tralbum]');
                if (el) {
                  const data = JSON.parse(el.getAttribute('data-tralbum'));
                  if (data.current && data.current.minimum_price != null) return data.current.minimum_price;
                  if (data.minimum_price_nonzero != null) return data.minimum_price_nonzero;
                  if (data.minimum_price != null) return data.minimum_price;
                  if (data.current && data.current.price != null) return data.current.price;
                }
                const ldEl = document.querySelector('script[type="application/ld+json"]');
                if (ldEl) {
                  const ld = JSON.parse(ldEl.innerText);
                  const offer = Array.isArray(ld.offers) ? ld.offers[0] : ld.offers;
                  if (offer && offer.price != null) return parseFloat(offer.price);
                }
                return 0;
              };
              const getID = () => {
                if (window.TralbumData) return window.TralbumData.id;
                const el = document.querySelector('[data-tralbum]');
                if (el) return JSON.parse(el.getAttribute('data-tralbum')).id;
                const idEl = document.querySelector('[data-item-id]');
                if (idEl) return idEl.getAttribute('data-item-id');
                return null;
              };
              const id = getID();
              const price = getPrice();
              if (!id) return null;
              const type = window.location.href.includes('/album/') ? 'a' : 't';
              const res = await fetch(window.location.origin + '/cart/cb', {
                method: 'POST',
                headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                body: 'req=add&item_type=' + type + '&item_id=' + id + '&unit_price=' + price + '&quantity=1&local_id=lc' + Date.now() + '&sync_num=${num}&cart_length=' + cartCount
              });
              const data = await res.json();
              if (data && (data.id || data.resync === true || data.ok === true)) return 'OK:' + price;
              return 'ERR:' + JSON.stringify(data);
            } catch(e) { return 'ERR:' + e.message; }
          })()`,
          awaitPromise: true, returnByValue: true
        }, sid);
        const res = r.result?.result?.value;
        if (res) {
          if (res.startsWith("OK:")) {
            val = "OK"; priceInfo = res.split(":")[1]; cartCount++;
          } else { val = res; }
          break;
        }
      }

      if (val === "OK") { console.log("OK (Preis: " + priceInfo + ")"); success++; }
      else { console.log("FEHLER (" + val.substring(0, 50) + "...)"); fail++; }
      await send("Target.closeTarget", { targetId: tid });
    } catch (e) { fail++; }
  }

  if (success > 0 || fail > 0) {
    console.log("\nÖffne Warenkorb...");
    const ar = await send("Target.attachToTarget", { targetId: mainTid, flatten: true });
    await send("Page.navigate", { url: "https://bandcamp.com/cart" }, ar.result.sessionId);
    await send("Target.activateTarget", { targetId: mainTid });
    await sleep(2000);
  }
}
main().catch(e => { console.error(e); process.exit(1); });
NODEEOF

# --- START ---
if ! curl -s "http://127.0.0.1:9222/json/version" &>/dev/null; then
  "$CHROME" --remote-debugging-port=9222 --user-data-dir="${TEMP:-/tmp}/bc-cart-profile" --no-first-run --no-default-browser-check about:blank &>/dev/null &
  sleep 3
fi

URLS_JSON="["$(printf '"%s",' "${URLS[@]}" | sed 's/,$//')"]"
node "$TMP_JS" "9222" "$URLS_JSON"
rm -f "$TMP_JS"
echo ""
read -p "Fertig. Enter zum Beenden (Browser bleibt offen)..."
