# 🎵 Bandcamp Auto-Cart

> 🛒 Automatisch Tracks & Alben von Bandcamp in den Warenkorb legen — ohne Login!

## ✨ Features

- 🚀 **Automatisches Hinzufügen** — legt alle Links aus einer Textdatei in den Warenkorb
- 🔓 **Ohne Anmeldung** — Login erst beim Checkout nötig
- 📂 **Einfache Konfiguration** — eine `bandcamp.txt` mit URLs, eine pro Zeile
- 🌐 **Tracks & Alben** — unterstützt beides automatisch
- 🛍️ **Auto-Checkout** — öffnet den Warenkorb am Ende automatisch

## 📋 Voraussetzungen

| 📁 Script | 🛠️ Benötigt | 💻 Plattform |
|-----------|-------------|-------------|
| `bandcamp-cart.ps1` | **Nichts** ✅ | Windows (vorinstalliert) |
| `bandcamp-cart.sh` | [Git Bash](https://git-scm.com/downloads) | Windows / Linux / Mac |

> 💡 **Empfehlung:** Die `.ps1` (PowerShell) Version — läuft sofort ohne Installation!

## 📁 Struktur

```
bandcam.com/
├── bandcamp-cart.ps1  🤖 PowerShell-Script (empfohlen)
├── bandcamp-cart.sh   🐧 Bash-Script (Linux/Mac/Git Bash)
├── bandcamp.txt       🔗 Deine Bandcamp-URLs
└── README.md          📖 Diese Datei
```

## 🚀 Schnellstart

### 1️⃣ URLs in `bandcamp.txt` eintragen

```text
https://lospepes.bandcamp.com/track/sweet-appeasement-2
https://michaelsimmons.bandcamp.com/track/thats-all-feat-nicole-kubis
https://rumbarrecords.bandcamp.com/track/bye-bye-love
```

> 💡 **Tipp:** Eine URL pro Zeile. Leerzeilen und Zeilen mit `#` werden ignoriert.

### 2️⃣ Script starten

**Option A — PowerShell (empfohlen, keine Installation):**
🖱️ Rechtsklick auf `bandcamp-cart.ps1` → **Mit PowerShell ausführen**

> ⚠️ Falls es nicht startet: PowerShell öffnen und eingeben:
> ```powershell
> powershell -ExecutionPolicy Bypass -File bandcamp-cart.ps1
> ```

**Option B — Bash (Git Bash oder Linux/Mac):**
```bash
bash bandcamp-cart.sh
```

### 3️⃣ Warenkorb öffnet sich automatisch

🛍️ Du siehst alle Titel im Warenkorb → auf **Checkout** klicken → bezahlen! 💳

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

## 🔧 Konfiguration

### URLs hinzufügen

Öffne `bandcamp.txt` und füge neue Zeilen hinzu:

```text
# 🎸 Meine Lieblings-Songs
https://artist1.bandcamp.com/track/song-name
https://artist2.bandcamp.com/album/album-name

# 🎹 Noch mehr Musik
https://artist3.bandcamp.com/track/another-song
```

### Unterstützte URL-Formate

| 🎵 Typ | 📝 Beispiel |
|--------|------------|
| Track | `https://artist.bandcamp.com/track/song-name` |
| Album | `https://artist.bandcamp.com/album/album-name` |

## ⚙️ Wie funktioniert das?

```
┌─────────────────────────────────────────────────┐
│  1. 📥 bandcamp.txt wird gelesen                │
│  2. 🌐 Für jede URL wird die Seite geladen      │
│  3. 🔍 Item-ID wird aus dem HTML extrahiert     │
│  4. 🛒 POST an /cart/cb API → Warenkorb         │
│  5. 🔄 Wiederholen für alle URLs                │
│  6. 🌍 Warenkorb wird im Browser geöffnet       │
└─────────────────────────────────────────────────┘
```

## ❓ FAQ

### 🤔 Muss ich mich anmelden?

> ❌ **Nein** — Bandcamp legt alles in einen anonymen Warenkorb. Du meldest dich erst beim Checkout an.

### 💰 Was wenn ein Track Geld kostet?

> ✅ **Kein Problem** — der Preis wird automatisch im Warenkorb angezeigt. Du siehst alles vor dem Bezahlen.

### 🔄 Kann ich die Links nochmal hinzufügen?

> 🗑️ Der Warenkorb wird bei jedem Script-Durchlauf **geleert**. Einfach `bandcamp.txt` anpassen und nochmal starten.

### 🛡️ Ist das sicher?

> ✅ **Ja** — es wird nur die öffentliche Bandcamp-API verwendet. Keine Passwörter oder persönlichen Daten nötig.

### 🐧 Funktioniert das auf Linux/Mac?

> ✅ **Ja** — einfach `bash bandcamp-cart.sh` im Terminal ausführen. Nur die `start`-Zeile am Ende ist Windows-spezifisch.

## 📝 Lizenz

🆓 Kostenlos — mach damit was du willst!

---

<p align="center">
  🎶 Viel Spaß beim Musik kaufen! 🎶
</p>
