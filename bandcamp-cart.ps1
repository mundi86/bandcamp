#!/usr/bin/env pwsh
# Bandcamp Auto-Cart (Final Reliability Edition)
# Keine Installation nötig — nur Chrome/Edge + PowerShell.

$ErrorActionPreference = "SilentlyContinue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LinkFile  = Join-Path $ScriptDir "bandcamp.txt"

# --- URLs laden ---
if (-not (Test-Path $LinkFile)) {
    Write-Host "FEHLER: bandcamp.txt nicht gefunden!" -ForegroundColor Red
    Read-Host "Enter zum Beenden"; exit 1
}
$Urls = @(Get-Content $LinkFile | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") })
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
    if (-not $BrowserPath -and (Test-Path $_.p)) { $BrowserPath = $_.p; $BrowserName = $_.n }
}

# --- CDP via WebSocket ---
$script:CdpMsgId = 1000
$script:Ws = $null

function Connect-Cdp {
    $ver = Invoke-RestMethod "http://127.0.0.1:9222/json/version" -TimeoutSec 5
    $ws = New-Object Net.WebSockets.ClientWebSocket
    $ws.ConnectAsync([Uri]$ver.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
    $script:Ws = $ws
}

function Send-Cdp([string]$method, [hashtable]$params = @{}, [string]$sid = "") {
    $script:CdpMsgId++
    $id = $script:CdpMsgId
    $msg = @{ id = $id; method = $method; params = $params }
    if ($sid) { $msg.sessionId = $sid }
    $json = $msg | ConvertTo-Json -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $script:Ws.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
    return $id
}

function Wait-Reply([int]$targetId, [int]$timeoutMs = 15000) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
        $fullMsg = ""; $isEnd = $false
        do {
            $buf = New-Object byte[] 262144
            $cts = New-Object Threading.CancellationTokenSource(3000)
            try {
                $res = $script:Ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $cts.Token).Result
                $fullMsg += [Text.Encoding]::UTF8.GetString($buf, 0, $res.Count)
                $isEnd = $res.EndOfMessage
            } catch { $isEnd = $true; break }
        } while (-not $isEnd)
        if ($fullMsg) {
            $obj = $fullMsg | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($obj -and $obj.id -eq $targetId) { return $obj }
        }
    }
    return $null
}

# ==========================================
#   START
# ==========================================
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Bandcamp -> Warenkorb (Reliable Mode)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Browser prüfen/starten
$portOpen = $false
try { $v = Invoke-RestMethod "http://127.0.0.1:9222/json/version" -TimeoutSec 1; $portOpen = $true } catch {}
if (-not $portOpen) {
    Start-Process $BrowserPath "--remote-debugging-port=9222 --user-data-dir=$env:TEMP\bc-cart-profile --no-first-run"
    Start-Sleep -Seconds 3
}

try { Connect-Cdp } catch { Write-Host "FEHLER: Konnte keine Verbindung zum Browser herstellen." -ForegroundColor Red; exit 1 }

# Einen Tab für alles nutzen
$cr = Wait-Reply (Send-Cdp "Target.createTarget" @{ url = "about:blank" })
$tid = $cr.result.targetId
$ar = Wait-Reply (Send-Cdp "Target.attachToTarget" @{ targetId = $tid; flatten = $true })
$sid = $ar.result.sessionId
Send-Cdp "Runtime.enable" @{} $sid | Out-Null

$Success = 0; $Fail = 0
$Total = $Urls.Count

for ($i = 0; $i -lt $Total; $i++) {
    $url = $Urls[$i].Trim()
    $num = $i + 1
    $label = ($url -split "/")[-1]
    Write-Host "[$num/$Total] $label ... " -NoNewline

    Send-Cdp "Page.navigate" @{ url = $url } $sid | Out-Null
    
    $result = "TIMEOUT"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 20000) {
        Start-Sleep -Milliseconds 800
        $js = @"
(async () => {
    try {
        if (!document.body || !window.fetch) return "WAIT:init";
        
        // ID Erkennung
        const id = (window.TralbumData && window.TralbumData.id) || 
                   (document.querySelector('[data-item-id]')?.dataset.itemId) ||
                   (document.documentElement.innerHTML.match(/item[-_]id[:"]{1,2}\s*(\d+)/i)?.[1]);
        if (!id) return "WAIT:id";
        
        const type = window.location.href.includes('/album/') ? 'a' : 't';
        const localId = 'lc' + Date.now();
        
        // Request mit vollständigen Parametern um resync:true zu vermeiden
        const res = await fetch(window.location.origin + '/cart/cb', {
            method: 'POST',
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'req=add&item_type=' + type + '&item_id=' + id + '&quantity=1&local_id=' + localId + '&sync_num=' + ($i + 1) + '&cart_length=' + $i
        });
        
        const d = await res.json();
        // Falls d.id vorhanden ist ODER d.resync:true (was oft bedeutet, dass es bereits drin ist oder nun synchronisiert ist)
        if (d && (d.id || d.resync === true || d.ok === true)) return 'OK';
        return 'ERR:' + JSON.stringify(d);
    } catch(e) { return 'ERR:' + e.message; }
})()
"@
        $rid = Send-Cdp "Runtime.evaluate" @{ expression = $js; awaitPromise = $true; returnByValue = $true } $sid
        $reply = Wait-Reply $rid 5000
        $val = $reply.result.result.value
        if ($val -and $val -notmatch "^WAIT:") {
            $result = $val
            break
        }
    }

    if ($result -eq "OK") {
        Write-Host "OK" -ForegroundColor Green
        $Success++
    } else {
        Write-Host "FEHLER ($result)" -ForegroundColor Red
        $Fail++
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Ergebnis: $Success OK / $Fail Fehler" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if ($Success -gt 0) {
    Write-Host "Öffne Warenkorb..."
    Send-Cdp "Page.navigate" @{ url = "https://bandcamp.com/cart" } $sid | Out-Null
}

Write-Host ""
Write-Host "Browser offen lassen -> Checkout klicken!"
Read-Host "Enter zum Beenden des Scripts"
