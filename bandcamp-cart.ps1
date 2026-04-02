#!/usr/bin/env pwsh
# Bandcamp Auto-Cart (nur PowerShell — keine Installation nötig!)
# Startet Chrome/Edge mit Remote Debugging und fügt alles per JavaScript im Browser hinzu.
#
# Ausführen: Rechtsklick → Mit PowerShell ausführen

$ErrorActionPreference = "SilentlyContinue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LinkFile  = Join-Path $ScriptDir "bandcamp.txt"

# --- URLs laden ---
if (-not (Test-Path $LinkFile)) {
    Write-Host "FEHLER: bandcamp.txt nicht gefunden!" -ForegroundColor Red
    Read-Host "Enter zum Beenden"; exit 1
}
$Urls = Get-Content $LinkFile | Where-Object {
    $l = $_.Trim(); $l -ne "" -and -not $l.StartsWith("#")
}
if ($Urls.Count -eq 0) {
    Write-Host "FEHLER: Keine URLs in bandcamp.txt!" -ForegroundColor Red
    Read-Host "Enter zum Beenden"; exit 1
}

# --- Browser finden ---
$BrowserPath = $null
$BrowserName = ""
@(
    @{p="${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"; n="Chrome"},
    @{p="${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"; n="Chrome"},
    @{p="$env:LocalAppData\Google\Chrome\Application\chrome.exe"; n="Chrome"},
    @{p="${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"; n="Edge"},
    @{p="${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"; n="Edge"}
) | ForEach-Object {
    if (-not $BrowserPath -and (Test-Path $_.p)) {
        $BrowserPath = $_.p
        $BrowserName = $_.n
    }
}
if (-not $BrowserPath) {
    Write-Host "FEHLER: Chrome oder Edge nicht gefunden!" -ForegroundColor Red
    Read-Host "Enter zum Beenden"; exit 1
}

# --- Funktionen ---
function Invoke-CdpEval {
    param([string]$Expression)
    $encoded = [Uri]::EscapeDataString($Expression)
    $url = "http://127.0.0.1:9222/json/evaluate?expression=$encoded"
    try {
        $resp = Invoke-RestMethod -Uri $url -Method Put -TimeoutSec 15
        return $resp.result.value
    } catch { return $null }
}

# --- Browser mit DevTools starten ---
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Bandcamp → Warenkorb (automatisch)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Browser: $BrowserName"
Write-Host "Quelle:  bandcamp.txt"
Write-Host "Titel:   $($Urls.Count)"
Write-Host ""

$proc = Start-Process $BrowserPath `
    "--remote-debugging-port=9222 --user-data-dir=$env:TEMP\bc-cart" `
    -PassThru

Write-Host "Warte auf Browser..." -NoNewline
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        Invoke-RestMethod "http://127.0.0.1:9222/json/version" -TimeoutSec 1 | Out-Null
        $ready = $true
        break
    } catch {}
}
if (-not $ready) {
    Write-Host " FEHLER" -ForegroundColor Red
    $proc.Kill()
    Read-Host "Enter zum Beenden"; exit 1
}
Write-Host " OK" -ForegroundColor Green
Write-Host ""

# --- Items hinzufügen ---
$Success = 0
$Fail = 0

for ($i = 0; $i -lt $Urls.Count; $i++) {
    $num = $i + 1
    $url = $Urls[$i].Trim()
    $label = ($url -split "/")[-1]
    Write-Host "[$num/$($Urls.Count)] $label ... " -NoNewline

    # URL laden
    $encodedUrl = [Uri]::EscapeDataString($url)
    Invoke-RestMethod "http://127.0.0.1:9222/json/new?$encodedUrl" -Method Put -TimeoutSec 10 | Out-Null
    Start-Sleep -Seconds 4

    # Item-Typ bestimmen
    $itemType = if ($url -match "/album/") { "a" } else { "t" }

    # JavaScript im Browser ausführen: Seite laden, item_id extrahieren, zum Warenkorb hinzufügen
    $js = @'
(async function() {
    try {
        var p = await fetch("URL_PLACEHOLDER");
        var h = await p.text();
        var m = h.match(/item_id.{0,5}?(\d{5,})/);
        if (!m) return "ERR:no_item_id";
        var id = m[1];
        var r = await fetch(window.location.origin + "/cart/cb", {
            method: "POST",
            headers: {"Content-Type": "application/x-www-form-urlencoded"},
            body: "req=add&item_type=TYPE_PLACEHOLDER&item_id=" + id + "&unit_price=0&quantity=1&local_id=lcNUM_PLACEHOLDER&sync_num=NUM_PLACEHOLDER&cart_length=CARTLEN_PLACEHOLDER"
        });
        var d = await r.json();
        return d.id ? "OK:" + d.id : "ERR:" + (d.error_message || "unknown");
    } catch(e) { return "ERR:" + e.message; }
})()
'@
    $js = $js.Replace("URL_PLACEHOLDER", $url)
    $js = $js.Replace("TYPE_PLACEHOLDER", $itemType)
    $js = $js.Replace("NUM_PLACEHOLDER", $num.ToString())
    $js = $js.Replace("CARTLEN_PLACEHOLDER", ($num - 1).ToString())

    $result = Invoke-CdpEval $js

    if ($result -and $result.StartsWith("OK:")) {
        $cartId = $result -replace "OK:", ""
        Write-Host "OK (Cart-ID: $cartId)" -ForegroundColor Green
        $Success++
    } elseif ($result -and $result.StartsWith("ERR:")) {
        $msg = $result -replace "ERR:", ""
        Write-Host "FEHLER ($msg)" -ForegroundColor Red
        $Fail++
    } else {
        Write-Host "UNBEKANNT" -ForegroundColor Yellow
        $Fail++
    }

    Start-Sleep -Seconds 1
}

# --- Ergebnis ---
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Ergebnis: $Success OK / $Fail Fehler" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if ($Success -gt 0) {
    Write-Host ""
    Write-Host "Öffne Warenkorb zum Bezahlen..." -ForegroundColor Green
    $encodedCart = [Uri]::EscapeDataString("https://bandcamp.com/cart")
    Invoke-RestMethod "http://127.0.0.1:9222/json/new?$encodedCart" -Method Put -TimeoutSec 10 | Out-Null
}

Write-Host ""
Write-Host "Browser offen lassen → Checkout klicken!"
Write-Host ""
Read-Host "Enter zum Beenden"
