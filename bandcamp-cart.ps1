# Bandcamp Auto-Cart
# Liest URLs aus bandcamp.txt und legt sie automatisch in den Warenkorb.
# Ohne Login — kein Git Bash nötig!
#
# Ausführen: Rechtsklick → "Mit PowerShell ausführen"
#            oder: powershell -ExecutionPolicy Bypass -File bandcamp-cart.ps1

$ErrorActionPreference = "SilentlyContinue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LinkFile  = Join-Path $ScriptDir "bandcamp.txt"
$Headers   = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
}

# --- Session für Cookies ---
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

# --- Prüfen ob bandcamp.txt existiert ---
if (-not (Test-Path $LinkFile)) {
    Write-Host ""
    Write-Host "FEHLER: bandcamp.txt nicht gefunden!" -ForegroundColor Red
    Write-Host "Erwartet: $LinkFile"
    Write-Host ""
    Write-Host "Lege eine Datei 'bandcamp.txt' neben das Script."
    Write-Host "Eine Bandcamp-URL pro Zeile."
    Write-Host ""
    Read-Host "Enter zum Beenden"
    exit 1
}

# --- URLs aus Datei lesen ---
$Urls = Get-Content $LinkFile | Where-Object {
    $line = $_.Trim()
    $line -ne "" -and -not $line.StartsWith("#")
}

if ($Urls.Count -eq 0) {
    Write-Host ""
    Write-Host "FEHLER: Keine URLs in bandcamp.txt gefunden!" -ForegroundColor Red
    Write-Host ""
    Read-Host "Enter zum Beenden"
    exit 1
}

$Success  = 0
$Fail     = 0
$Sync     = 1
$CartLen  = 0

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Bandcamp → Warenkorb (automatisch)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Quelle: bandcamp.txt"
Write-Host "Titel:  $($Urls.Count)"
Write-Host ""

for ($i = 0; $i -lt $Urls.Count; $i++) {
    $num = $i + 1
    $url = $Urls[$i].Trim()
    $label = ($url -split "/")[-1]
    Write-Host "[$num/$($Urls.Count)] $label ... " -NoNewline

    # --- Subdomain (Artist) extrahieren ---
    if ($url -match "https://([^.]+)\.bandcamp\.com") {
        $artist = $Matches[1]
    } else {
        Write-Host "FEHLER (ungültige URL)" -ForegroundColor Red
        $Fail++
        continue
    }
    $cartUrl = "https://$artist.bandcamp.com/cart/cb"

    # --- Seite laden & item_id extrahieren ---
    try {
        $page = Invoke-WebRequest -Uri $url -WebSession $session -Headers $Headers -UseBasicParsing
        $html = $page.Content
    } catch {
        Write-Host "FEHLER (Seite nicht ladbar)" -ForegroundColor Red
        $Fail++
        Start-Sleep -Seconds 1
        continue
    }

    $itemId = $null
    if ($html -match 'item_id&quot;:(\d+)') {
        $itemId = $Matches[1]
    } elseif ($html -match 'item_id":(\d+)') {
        $itemId = $Matches[1]
    } elseif ($html -match 'data-item-id="(\d+)"') {
        $itemId = $Matches[1]
    }

    if (-not $itemId) {
        Write-Host "FEHLER (item_id nicht gefunden)" -ForegroundColor Red
        $Fail++
        Start-Sleep -Seconds 1
        continue
    }

    # --- Item-Typ bestimmen ---
    $itemType = if ($url -match "/album/") { "a" } else { "t" }

    # --- Zum Warenkorb hinzufügen ---
    $localId = "lc$(Get-Date -UFormat %s)$num"
    $body = @{
        req        = "add"
        item_type  = $itemType
        item_id    = $itemId
        unit_price = 0
        quantity   = 1
        local_id   = $localId
        sync_num   = $Sync
        cart_length = $CartLen
    }

    try {
        $resp = Invoke-RestMethod -Uri $cartUrl `
            -Method Post `
            -WebSession $session `
            -Headers @{
                "User-Agent" = $Headers["User-Agent"]
                "Origin"     = "https://$artist.bandcamp.com"
                "Referer"    = $url
            } `
            -Body $body

        if ($resp.id) {
            Write-Host "OK (Cart-ID: $($resp.id))" -ForegroundColor Green
            $Success++
            $Sync++
            $CartLen++
        } elseif ($resp.error) {
            Write-Host "FEHLER ($($resp.error_message))" -ForegroundColor Red
            $Fail++
        } else {
            Write-Host "UNBEKANNT" -ForegroundColor Yellow
            $Fail++
        }
    } catch {
        Write-Host "FEHLER (Request fehlgeschlagen)" -ForegroundColor Red
        $Fail++
    }

    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Ergebnis: $Success OK / $Fail Fehler" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if ($Success -gt 0) {
    Write-Host ""
    Write-Host "Öffne Warenkorb zum Bezahlen..." -ForegroundColor Green
    Start-Process "https://bandcamp.com/cart"
}

Write-Host ""
Read-Host "Enter zum Beenden"
