# Bandcamp → Warenkorb
# Öffnet alle Bandcamp-URLs im Browser. Klick auf "Buy" auf jeder Seite.
#
# Ausführen: Rechtsklick → Mit PowerShell ausführen
#            oder: powershell -ExecutionPolicy Bypass -File bandcamp-cart.ps1

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LinkFile  = Join-Path $ScriptDir "bandcamp.txt"

# --- Prüfen ob bandcamp.txt existiert ---
if (-not (Test-Path $LinkFile)) {
    Write-Host ""
    Write-Host "FEHLER: bandcamp.txt nicht gefunden!" -ForegroundColor Red
    Write-Host "Erwartet: $LinkFile"
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

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Bandcamp → Browser öffnen" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Quelle: bandcamp.txt"
Write-Host "Titel:  $($Urls.Count)"
Write-Host ""

for ($i = 0; $i -lt $Urls.Count; $i++) {
    $num = $i + 1
    $url = $Urls[$i].Trim()
    $label = ($url -split "/")[-1]
    Write-Host "[$num/$($Urls.Count)] $label"
    Start-Process $url
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Fertig!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Auf jeder Seite auf 'Buy' klicken."
Write-Host "Danach alles auf einmal bezahlen."
Write-Host ""
Read-Host "Enter zum Beenden"
