# 🎵 Bandcamp Auto-Cart (Parallel Edition)

> 🛒 Automatisch Tracks & Alben von Bandcamp in den Warenkorb legen — blitzschnell & parallel!

---

## ✨ Features

- 🚀 **Parallelverarbeitung** — Verarbeitet bis zu 5 Links gleichzeitig (Worker-Pool)
- ⚡ **Turbo-Modus** — Fügt Items zum Warenkorb hinzu, sobald die ID im HTML erscheint (kein Warten auf Bilder/Werbung)
- 🔒 **Ohne Anmeldung** — Login erst beim Checkout im Browser nötig
- 📂 **Einfache Konfiguration** — Eine `bandcamp.txt` mit URLs, eine pro Zeile
- 🌐 **Tracks & Alben** — Beides wird automatisch erkannt
- 🛍️ **Auto-Checkout** — Öffnet den Warenkorb am Ende automatisch im Browser
- 💻 **Plattformübergreifend** — Windows, Mac & Linux

---

## 📋 Voraussetzungen

| 💻 System | 📜 Script | 🛠️ Installation nötig? |
|----------|----------|----------------------|
| **Windows** | `bandcamp-cart.ps1` | ✔️ Chrome oder Edge erforderlich |
| **Mac** | `bandcamp-cart.sh` | 🟢 [Node.js v22+](https://nodejs.org) erforderlich |
| **Linux** | `bandcamp-cart.sh` | 🟢 [Node.js v22+](https://nodejs.org) erforderlich |

---

## 📂 Dateien

```
bandcam.com/
├── bandcamp-cart.ps1  ⚡ PowerShell-Script (Windows)
├── bandcamp-cart.sh   🚀 Bash-Script (Mac / Linux / Git Bash)
├── bandcamp.txt       🔗 Deine Bandcamp-URLs
└── README.md          📖 Dokumentation
```

---

## 🚀 Los geht's

### 1️⃣ URLs in `bandcamp.txt` eintragen

Füge deine Bandcamp-Links in die `bandcamp.txt` ein — **eine URL pro Zeile**:

```text
https://artist.bandcamp.com/track/song-name
https://artist.bandcamp.com/album/album-name
```

### 2️⃣ Script starten

**🪟 Windows:**

Rechtsklick auf `bandcamp-cart.ps1` → **Mit PowerShell ausführen**

Oder über die Konsole:
```powershell
powershell -ExecutionPolicy Bypass -File bandcamp-cart.ps1
```

**🍎 Mac / 🐧 Linux:**

Stelle sicher, dass Node.js installiert ist (`node -v` sollte v22 oder höher zeigen).
```bash
bash bandcamp-cart.sh
```

### 3️⃣ Bezahlen

🛒 Der Warenkorb öffnet sich automatisch → **Checkout** klicken → fertig!

---

## ⚙️ Ablauf (Technisch)

1. **Browser-Control**: Das Script verbindet sich per **Chrome DevTools Protocol (CDP)** mit einem Browser-Fenster.
2. **Worker-Pool**: Es werden 5 parallele Tabs geöffnet.
3. **Aggressives Polling**: Sobald die `item_id` im DOM der Seite auftaucht, wird der Warenkorb-POST-Request abgesetzt.
4. **Zentralisierung**: Alle Items landen in derselben anonymen Session im Browser.

---

## 📜 Lizenz

[MIT License](LICENSE) — kostenlos, open source.

🎶 Viel Spaß beim Musik kaufen! 🎶
