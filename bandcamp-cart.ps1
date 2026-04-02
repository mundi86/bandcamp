#!/usr/bin/env pwsh
# Bandcamp Auto-Cart (Turbo Edition)
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
            $buf = New-Object byte[] 131072
            $cts = New-Object Threading.CancellationTokenSource(2000)
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
Write-Host "  Bandcamp -> Warenkorb (Turbo Mode)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Browser: $BrowserName"
Write-Host "Titel:   $($Urls.Count)"
Write-Host ""

# Browser prüfen/starten
$portOpen = $false
try { $v = Invoke-RestMethod "http://127.0.0.1:9222/json/version" -TimeoutSec 1; $portOpen = $true } catch {}
if (-not $portOpen) {
    Start-Process $BrowserPath "--remote-debugging-port=9222 --user-data-dir=$env:TEMP\bc-cart-profile"
    Start-Sleep -Seconds 2
}

try { Connect-Cdp } catch { Write-Host "FEHLER: Konnte keine Verbindung zum Browser herstellen." -ForegroundColor Red; exit 1 }

$Success = 0; $Fail = 0
$Total = $Urls.Count

for ($i = 0; $i -lt $Total; $i++) {
    $url = $Urls[$i].Trim()
    $num = $i + 1
    $label = ($url -split "/")[-1]
    Write-Host "[$num/$Total] $label ... " -NoNewline

    # Tab erstellen & Attach
    $cr = Wait-Reply (Send-Cdp "Target.createTarget" @{ url = "about:blank" })
    $tid = $cr.result.targetId
    $ar = Wait-Reply (Send-Cdp "Target.attachToTarget" @{ targetId = $tid; flatten = $true })
    $sid = $ar.result.sessionId
    
    Send-Cdp "Page.navigate" @{ url = $url } $sid | Out-Null
    
    # Turbo Polling: ID suchen & Add to Cart
    $result = "TIMEOUT"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 15000) {
        Start-Sleep -Milliseconds 500
        $js = @"
(async () => {
    try {
        const h = document.documentElement.innerHTML;
        const m = h.match(/\"item_id\":\s*(\d+)/) || h.match(/data-item-id=\"(\d+)\"/) || h.match(/item[-_]id.{0,10}?(\d{5,})/);
        if (!m) return null;
        
        const type = window.location.href.includes('/album/') ? 'a' : 't';
        const r = await fetch(window.location.origin + '/cart/cb', {
            method: 'POST',
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'req=add&item_type=' + type + '&item_id=' + m[1] + '&unit_price=0&quantity=1&local_id=lc'+Date.now()+'&sync_num=$num&cart_length=0'
        });
        const d = await r.json();
        return d.id ? 'OK:' + d.id : 'ERR:' + (d.error_message || 'unknown');
    } catch(e) { return 'ERR:' + e.message; }
})()
"@
        $rid = Send-Cdp "Runtime.evaluate" @{ expression = $js; awaitPromise = $true; returnByValue = $true } $sid
        $reply = Wait-Reply $rid 3000
        if ($reply.result.result.value) {
            $result = $reply.result.result.value
            break
        }
    }

    if ($result.StartsWith("OK:")) {
        Write-Host "OK" -ForegroundColor Green
        $Success++
    } else {
        Write-Host "FEHLER ($result)" -ForegroundColor Red
        $Fail++
    }
    
    Send-Cdp "Target.closeTarget" @{ targetId = $tid } | Out-Null
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Ergebnis: $Success OK / $Fail Fehler" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if ($Success -gt 0) {
    Send-Cdp "Target.createTarget" @{ url = "https://bandcamp.com/cart" } | Out-Null
}

Write-Host ""
Write-Host "Browser offen lassen -> Checkout klicken!"
Read-Host "Enter zum Beenden"
