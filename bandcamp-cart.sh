#!/bin/bash
# Bandcamp Auto-Cart (Perfect Price Edition)
# Benötigt: Chrome + Node.js (v22+)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_FILE="${SCRIPT_DIR}/bandcamp.txt"
DEBUG_PORT=9222
TMP_ROOT="${TEMP:-${TMPDIR:-/tmp}}"
TMP_JS="$(mktemp "${TMP_ROOT%/}/bc_helper_XXXXXX.js")"

cleanup() {
  rm -f "$TMP_JS"
}
trap cleanup EXIT

trim_line() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# --- URLs laden ---
[ ! -f "$LINK_FILE" ] && { echo "FEHLER: bandcamp.txt fehlt!"; exit 1; }
URLS=()
while IFS= read -r line; do
  line="$(printf '%s' "$line" | trim_line)"
  [ -z "$line" ] || [[ "$line" == \#* ]] || URLS+=("$line")
done < "$LINK_FILE"
[ ${#URLS[@]} -eq 0 ] && { echo "FEHLER: Keine URLs!"; exit 1; }

# --- Node.js & Chrome finden ---
command -v node >/dev/null 2>&1 || { echo "FEHLER: Node.js fehlt!"; exit 1; }
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
[ ! -f "$CHROME" ] && CHROME="${LOCALAPPDATA:-}/Google/Chrome/Application/chrome.exe"
[ ! -f "$CHROME" ] && CHROME="$(command -v google-chrome || command -v chromium || true)"
[ -n "$CHROME" ] && [ -f "$CHROME" ] || command -v "$CHROME" >/dev/null 2>&1 || {
  echo "FEHLER: Kein kompatibler Chrome/Chromium-Browser gefunden!"
  exit 1
}

# --- Node.js CDP Helper ---
cat <<'NODEEOF' > "$TMP_JS"
const WebSocket = global.WebSocket || (typeof WebSocket !== "undefined" ? WebSocket : null);
const http = require("http");
const port = process.argv[2] || 9222;
const urls = JSON.parse(process.argv[3] || "[]");

function httpGet(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = "";
      res.on("data", (chunk) => { data += chunk; });
      res.on("end", () => resolve(JSON.parse(data)));
    }).on("error", reject);
  });
}

async function main() {
  if (!WebSocket) {
    throw new Error("Node.js braucht eine verfügbare WebSocket-Implementierung.");
  }

  const ver = await httpGet(`http://127.0.0.1:${port}/json/version`);
  const ws = new WebSocket(ver.webSocketDebuggerUrl);
  let msgId = 100;
  const pending = {};

  ws.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending[message.id]) {
      pending[message.id](message);
      delete pending[message.id];
    }
  };

  const send = (method, params = {}, sessionId = null) => new Promise((resolve) => {
    const id = ++msgId;
    const message = { id, method, params };
    if (sessionId) {
      message.sessionId = sessionId;
    }
    pending[id] = resolve;
    ws.send(JSON.stringify(message));
  });

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  await new Promise((resolve) => { ws.onopen = resolve; });

  const targets = await httpGet(`http://127.0.0.1:${port}/json/list`);
  if (!Array.isArray(targets) || targets.length === 0) {
    throw new Error("Kein offener Browser-Tab für den Anchor gefunden.");
  }
  const mainTid = targets[0].id;

  let success = 0;
  let fail = 0;
  let cartCount = 0;

  for (let i = 0; i < urls.length; i += 1) {
    const url = urls[i].trim();
    const num = i + 1;
    const label = url.split("/").filter(Boolean).pop() || url;
    process.stdout.write(`[${num}/${urls.length}] ${label} ... `);

    let tid = null;
    try {
      const createdTarget = await send("Target.createTarget", { url: "about:blank" });
      tid = createdTarget.result.targetId;
      const attachedTarget = await send("Target.attachToTarget", { targetId: tid, flatten: true });
      const sid = attachedTarget.result.sessionId;

      await send("Runtime.enable", {}, sid);
      await send("Page.navigate", { url }, sid);

      let result = "TIMEOUT";
      let priceInfo = "0.00";

      for (let t = 0; t < 25; t += 1) {
        await sleep(1000);
        const evaluation = await send("Runtime.evaluate", {
          expression: `(async () => {
            try {
              const getPrice = () => {
                // Bandcamp liefert den Mindestpreis je nach Layout an unterschiedlichen Stellen aus.
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

              // cart_length und sync_num halten die Server-Session konsistent, wenn mehrere Items folgen.
              const type = window.location.href.includes('/album/') ? 'a' : 't';
              const res = await fetch(window.location.origin + '/cart/cb', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: 'req=add&item_type=' + type + '&item_id=' + id + '&unit_price=' + price + '&quantity=1&local_id=lc' + Date.now() + '&sync_num=${num}&cart_length=${cartCount}'
              });
              const data = await res.json();
              if (data && (data.id || data.resync === true || data.ok === true)) return 'OK:' + price;
              return 'ERR:' + JSON.stringify(data);
            } catch (e) {
              return 'ERR:' + e.message;
            }
          })()`,
          awaitPromise: true,
          returnByValue: true,
        }, sid);

        const value = evaluation.result?.result?.value;
        if (value) {
          if (value.startsWith("OK:")) {
            result = "OK";
            priceInfo = value.split(":")[1];
          } else {
            result = value;
          }
          break;
        }
      }

      if (result === "OK") {
        console.log(`OK (Preis: ${priceInfo})`);
        success += 1;
        cartCount += 1;
      } else {
        console.log(`FEHLER (${String(result).substring(0, 80)}...)`);
        fail += 1;
      }
    } catch (e) {
      console.log(`FEHLER (${e.message})`);
      fail += 1;
    } finally {
      if (tid) {
        await send("Target.closeTarget", { targetId: tid });
      }
    }
  }

  if (success > 0 || fail > 0) {
    console.log("\\nÖffne Warenkorb...");
    const anchorTarget = await send("Target.attachToTarget", { targetId: mainTid, flatten: true });
    await send("Page.navigate", { url: "https://bandcamp.com/cart" }, anchorTarget.result.sessionId);
    await send("Target.activateTarget", { targetId: mainTid });
    await sleep(2000);
  }
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
NODEEOF

# --- START ---
if ! curl -fsS "http://127.0.0.1:${DEBUG_PORT}/json/version" >/dev/null 2>&1; then
  "$CHROME" \
    --remote-debugging-port="${DEBUG_PORT}" \
    --user-data-dir="${TMP_ROOT%/}/bc-cart-profile" \
    --no-first-run \
    --no-default-browser-check \
    about:blank >/dev/null 2>&1 &
  sleep 3
fi

URLS_JSON="$(node -e 'console.log(JSON.stringify(process.argv.slice(1)))' "${URLS[@]}")"
node "$TMP_JS" "$DEBUG_PORT" "$URLS_JSON"
echo ""
read -r -p "Fertig. Enter zum Beenden (Browser bleibt offen)..."
