# 🎵 Bandcamp Auto-Cart (Perfect Price Edition)

> 🛒 Automatisch Tracks & Alben von Bandcamp in den Warenkorb legen — jetzt so stabil und präzise wie nie zuvor!

---

## ✨ Features

- 💰 **Deep Price Detection** — Erkennt automatisch den korrekten Mindestpreis (wichtig für den Checkout!).
- 🪟 **Single-Window Logic** — Alles findet in einem einzigen Browser-Fenster statt (kein Fenster-Chaos mehr).
- ⚡ **Turbo Sync** — Optimierte Übermittlung an die Bandcamp-API für maximale Geschwindigkeit.
- 🎯 **Auto-Focus** — Der Warenkorb wird am Ende automatisch aktiviert und in den Vordergrund geholt.
- 🔒 **Sichere Session** — Nutzt ein isoliertes Browser-Profil für saubere Durchläufe.
- 💻 **Plattformübergreifend** — Identische Logik für Windows (`.ps1`) und Mac/Linux (`.sh`).

---

## 📋 Voraussetzungen

| 💻 System | 📜 Script | 🛠️ Benötigt |
|----------|----------|----------------------|
| **Windows** | `bandcamp-cart.ps1` | Chrome oder Edge |
| **Mac / Linux** | `bandcamp-cart.sh` | [Node.js v22+](https://nodejs.org) |

---

## 🚀 Los geht's

1. **URLs eintragen**: Füge deine Bandcamp-Links in die `bandcamp.txt` ein (eine URL pro Zeile).
2. **Script starten**:
   - **Windows**: Rechtsklick auf `bandcamp-cart.ps1` -> *Mit PowerShell ausführen*.
   - **Mac/Linux**: `bash bandcamp-cart.sh` im Terminal.
3. **Checkout**: Am Ende öffnet sich der Warenkorb mit den korrekten Preisen. Einfach auf *Checkout* klicken und fertig!

---

## ⚙️ Ablauf (Technisch)

1. **Anchor-Tab**: Das Script nutzt den ersten Tab als Anker, um den Browser-Prozess stabil zu halten.
2. **Dynamic Processing**: Für jeden Link wird kurzzeitig ein neuer Tab geöffnet, die Daten (ID & Preis) extrahiert und die API-Anfrage gesendet.
3. **Deep Search**: Das Script durchsucht `TralbumData`, HTML-Attribute und JSON-LD Daten nach dem exakten Preis.
4. **Final Navigation**: Der Anker-Tab navigiert am Ende zum Warenkorb.

---

## 📜 Lizenz

[MIT License](LICENSE) — kostenlos & open source.

🎶 *Viel Spaß beim Entdecken neuer Musik!* 🛒
