# 🎵 Bandcamp Auto-Cart

> 🛒 Automatisch Tracks & Alben von Bandcamp in den Warenkorb legen — ohne Login!

---

## ✨ Features

- 🚀 **Automatisches Hinzufügen** — alle Links aus einer Textdatei auf einmal in den Warenkorb
- 🔓 **Ohne Anmeldung** — Login erst beim Checkout nötig
- 📂 **Einfache Konfiguration** — eine `bandcamp.txt` mit URLs, eine pro Zeile
- 🌐 **Tracks & Alben** — beides wird automatisch erkannt
- 🛍️ **Auto-Checkout** — öffnet den Warenkorb am Ende automatisch im Browser
- 🖥️ **Plattformübergreifend** — Windows, Mac & Linux

---

## 📋 Voraussetzungen

| 💻 System | 📁 Script | 🛠️ Installation nötig? |
|----------|----------|----------------------|
| **Windows** | `bandcamp-cart.ps1` | ❌ Nein (PowerShell ist vorinstalliert) |
| **Mac** | `bandcamp-cart.sh` | ❌ Nein (bash & curl sind vorinstalliert) |
| **Linux** | `bandcamp-cart.sh` | ❌ Nein (bash & curl sind vorinstalliert) |
| **Windows + Bash** | `bandcamp-cart.sh` | [Git Bash](https://git-scm.com/downloads) |

> 💡 **Windows + Bash?** Prüfe ob Git Bash installiert ist: `git --version` in PowerShell eingeben. Falls eine Version erscheint, ist es bereits da. Falls nicht: [git-scm.com/downloads](https://git-scm.com/downloads)

---

## 📁 Dateien

```
bandcam.com/
├── bandcamp-cart.ps1  ⚡ PowerShell-Script (Windows)
├── bandcamp-cart.sh   🐧 Bash-Script (Mac / Linux)
├── bandcamp.txt       🔗 Deine Bandcamp-URLs
└── README.md          📖 Dokumentation
```

---

## 🚀 Los geht's

### 1️⃣ URLs in `bandcamp.txt` eintragen

Öffne `bandcamp.txt` und füge deine Bandcamp-Links ein — **eine URL pro Zeile**:

```text
https://lospepes.bandcamp.com/track/sweet-appeasement-2
https://michaelsimmons.bandcamp.com/track/thats-all-feat-nicole-kubis
https://rumbarrecords.bandcamp.com/track/bye-bye-love
https://sfapf.bandcamp.com/album/this-love
```

> 💡 Leerzeilen und Zeilen mit `#` werden ignoriert — so kannst du Kommentare schreiben:
> ```text
> # 🎸 Rock
> https://artist.bandcamp.com/track/song-name
> ```

### 2️⃣ Script starten

**🪟 Windows:**

Rechtsklick auf `bandcamp-cart.ps1` → **Mit PowerShell ausführen**

Falls es nicht startet, PowerShell öffnen und eingeben:
```powershell
powershell -ExecutionPolicy Bypass -File bandcamp-cart.ps1
```

**🍎 Mac / 🐧 Linux:**

Terminal öffnen und eingeben:
```bash
bash bandcamp-cart.sh
```

### 3️⃣ Bezahlen

🛍️ Der Warenkorb öffnet sich automatisch → **Checkout** klicken → fertig!

---

## 📖 Beispiel-Output

```
==========================================
  Bandcamp → Warenkorb (automatisch)
==========================================
Quelle: bandcamp.txt
Titel:  10

[1/10] sweet-appeasement-2 ... OK (Cart-ID: 378336948)
[2/10] thats-all-feat-nicole-kubis ... OK (Cart-ID: 378336977)
[3/10] bye-bye-love ... OK (Cart-ID: 378337001)
...

==========================================
  Ergebnis: 10 OK / 0 Fehler
==========================================

Öffne Warenkorb zum Bezahlen...
```

---

## 🔧 Unterstützte URL-Formate

| 🎵 Typ | 📝 Beispiel |
|--------|------------|
| Track | `https://artist.bandcamp.com/track/song-name` |
| Album | `https://artist.bandcamp.com/album/album-name` |

---

## ⚙️ Ablauf

```
┌──────────────────────────────────────────────────────┐
│  1. 📥  bandcamp.txt wird eingelesen                 │
│  2. 🌐  Für jede URL wird die Bandcamp-Seite geladen │
│  3. 🔍  Interne Item-ID wird aus dem HTML extrahiert │
│  4. 🛒  POST an /cart/cb API → Warenkorb             │
│  5. 🔄  Wiederholung für alle URLs                   │
│  6. 🌍  Warenkorb öffnet sich automatisch im Browser │
└──────────────────────────────────────────────────────┘
```

---

## ❓ FAQ

**🤔 Muss ich mich anmelden?**
> Nein. Bandcamp legt alles in einen anonymen Warenkorb. Du meldest dich erst beim Checkout an.

**💰 Was wenn ein Track Geld kostet?**
> Kein Problem. Der Preis wird automatisch im Warenkorb angezeigt. Du siehst alles bevor du bezahlst.

**🔄 Kann ich die Links nochmal hinzufügen?**
> Der Warenkorb wird bei jedem Script-Durchlauf geleert. Einfach `bandcamp.txt` anpassen und nochmal starten.

**🛡️ Ist das sicher?**
> Ja. Es wird nur die öffentliche Bandcamp-API verwendet. Keine Passwörter oder persönlichen Daten nötig.

---

## 📝 Lizenz

[MIT License](LICENSE) — kostenlos, open source, mach damit was du willst! 🆓

🎶 Viel Spaß beim Musik kaufen! 🎶
