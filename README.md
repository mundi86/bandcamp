# ðŸŽµ Bandcamp Auto-Cart (Parallel Edition)

> ðŸ›’ Automatisch Tracks & Alben von Bandcamp in den Warenkorb legen â€” blitzschnell & parallel!

---

## âœ¨ Features

- ðŸš€ **Parallelverarbeitung** â€” Verarbeitet bis zu 5 Links gleichzeitig (Worker-Pool)
- âš¡ **Turbo-Modus** â€” FÃ¼gt Items zum Warenkorb hinzu, sobald die ID im HTML erscheint (kein Warten auf Bilder/Werbung)
- ðŸ”’ **Ohne Anmeldung** â€” Login erst beim Checkout im Browser nÃ¶tig
- ðŸ“‚ **Einfache Konfiguration** â€” Eine `bandcamp.txt` mit URLs, eine pro Zeile
- ðŸŒ **Tracks & Alben** â€” Beides wird automatisch erkannt
- ðŸ›ï¸ **Auto-Checkout** â€” Ã–ffnet den Warenkorb am Ende automatisch im Browser
- ðŸ’» **PlattformÃ¼bergreifend** â€” Windows, Mac & Linux

---

## ðŸ“‹ Voraussetzungen

| ðŸ’» System | ðŸ“œ Script | ðŸ› ï¸ Installation nÃ¶tig? |
|----------|----------|----------------------|
| **Windows** | `bandcamp-cart.ps1` | âœ”ï¸ Chrome oder Edge erforderlich |
| **Mac** | `bandcamp-cart.sh` | ðŸŸ¢ [Node.js v22+](https://nodejs.org) erforderlich |
| **Linux** | `bandcamp-cart.sh` | ðŸŸ¢ [Node.js v22+](https://nodejs.org) erforderlich |

---

## ðŸ“‚ Dateien

```
bandcam.com/
â”œâ”€â”€ bandcamp-cart.ps1  âš¡ PowerShell-Script (Windows)
â”œâ”€â”€ bandcamp-cart.sh   ðŸš€ Bash-Script (Mac / Linux / Git Bash)
â”œâ”€â”€ bandcamp.txt       ðŸ”— Deine Bandcamp-URLs
â””â”€â”€ README.md          ðŸ“– Dokumentation
```

---

## ðŸš€ Los geht's

### 1ï¸âƒ£ URLs in `bandcamp.txt` eintragen

FÃ¼ge deine Bandcamp-Links in die `bandcamp.txt` ein â€” **eine URL pro Zeile**:

```text
https://artist.bandcamp.com/track/song-name
https://artist.bandcamp.com/album/album-name
```

### 2ï¸âƒ£ Script starten

**ðŸªŸ Windows:**

Rechtsklick auf `bandcamp-cart.ps1` â†’ **Mit PowerShell ausfÃ¼hren**

Oder Ã¼ber die Konsole:
```powershell
powershell -ExecutionPolicy Bypass -File bandcamp-cart.ps1
```

**ðŸŽ Mac / ðŸ§ Linux:**

Stelle sicher, dass Node.js installiert ist (`node -v` sollte v22 oder hÃ¶her zeigen).
```bash
bash bandcamp-cart.sh
```

### 3ï¸âƒ£ Bezahlen

ðŸ›’ Der Warenkorb Ã¶ffnet sich automatisch â†’ **Checkout** klicken â†’ fertig!

---

## âš™ï¸ Ablauf (Technisch)

1. **Browser-Control**: Das Script verbindet sich per **Chrome DevTools Protocol (CDP)** mit einem Browser-Fenster.
2. **Worker-Pool**: Es werden 5 parallele Tabs geÃ¶ffnet.
3. **Aggressives Polling**: Sobald die `item_id` im DOM der Seite auftaucht, wird der Warenkorb-POST-Request abgesetzt.
4. **Zentralisierung**: Alle Items landen in derselben anonymen Session im Browser.

---

## ðŸ“œ Lizenz

[MIT License](LICENSE) â€” kostenlos, open source.

ðŸŽ¶ Viel SpaÃŸ beim Musik kaufen! ðŸŽ¶

