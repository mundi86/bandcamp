#!/usr/bin/env pwsh
# Bandcamp Auto-Cart (Perfect Price Edition)
# Keine Installation nötig — nur Chrome/Edge + PowerShell.

$ErrorActionPreference = "SilentlyContinue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LinkFile  = Join-Path $ScriptDir "bandcamp.txt"

# --- URLs laden ---
if (-not (Test-Path $LinkFile)) { Write-Host "FEHLER: bandcamp.txt fehlt!" -ForegroundColor Red; exit 1 }
$Urls = @(Get-Content $LinkFile | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") })
if ($Urls.Count -eq 0) { Write-Host "FEHLER: Keine URLs!" -ForegroundColor Red; exit 1 }

# --- Browser finden ---
$BrowserPath = $null
@(
    @{p="${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"; n="Chrome"},
    @{p="${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"; n="Chrome"},
    @{p="$env:LocalAppData\Google\Chrome\Application\chrome.exe"; n="Chrome"},
    @{p="${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"; n="Edge"}
) | ForEach-Object { if (-not $BrowserPath -and (Test-Path $_.p)) { $BrowserPath = $_.p } }

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
    $script:CdpMsgId++; $id = $script:CdpMsgId
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

# --- START ---
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Bandcamp -> Warenkorb (Perfect Price)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$portOpen = $false
try { $v = Invoke-RestMethod "http://127.0.0.1:9222/json/version" -TimeoutSec 1; $portOpen = $true } catch {}
if (-not $portOpen) {
    Start-Process $BrowserPath "--remote-debugging-port=9222 --incognito --user-data-dir=$env:TEMP\bc-cart-profile-final --no-first-run"
    Start-Sleep -Seconds 3
}

try { Connect-Cdp } catch { Write-Host "FEHLER: Browser-Verbindung fehlgeschlagen." -ForegroundColor Red; exit 1 }

$mainCr = Wait-Reply (Send-Cdp "Target.createTarget" @{ url = "about:blank" })
$mainTid = $mainCr.result.targetId

$Success = 0; $Fail = 0
for ($i = 0; $i -lt $Urls.Count; $i++) {
    $url = $Urls[$i].Trim(); $num = $i + 1; $label = ($url -split "/")[-1]
    Write-Host "[$num/$($Urls.Count)] $label ... " -NoNewline

    $cr = Wait-Reply (Send-Cdp "Target.createTarget" @{ url = $url })
    $tid = $cr.result.targetId
    $ar = Wait-Reply (Send-Cdp "Target.attachToTarget" @{ targetId = $tid; flatten = $true })
    $sid = $ar.result.sessionId
    
    $result = "TIMEOUT"
    $detectedPrice = "0.00"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 20000) {
        Start-Sleep -Milliseconds 1000
        $js = @"
(async () => {
    try {
        const el = document.querySelector('[data-tralbum]');
        if (!el) return null;
        
        // 1. Daten extrahieren
        const data = JSON.parse(el.getAttribute('data-tralbum'));
        const id = data.id;
        const type = data.item_type === 'album' ? 'a' : 't';
        
        // 2. Preis extrahieren (minimum_price ist entscheidend)
        let price = data.minimum_price || (data.current && data.current.minimum_price) || (data.current && data.current.price) || 0;
        
        // 3. In den Warenkorb legen
        const res = await fetch(window.location.origin + '/cart/cb', {
            method: 'POST',
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'req=add&item_type=' + type + '&item_id=' + id + '&unit_price=' + price + '&quantity=1&local_id=lc' + Date.now() + '&sync_num=$num&cart_length=0'
        });
        const d = await res.json();
        if (d && (d.id || d.resync === true || d.ok === true)) return 'OK:' + price;
        return 'ERR:' + JSON.stringify(d);
    } catch(e) { return 'ERR:' + e.message; }
})()
"@
        $rid = Send-Cdp "Runtime.evaluate" @{ expression = $js; awaitPromise = $true; returnByValue = $true } $sid
        $reply = Wait-Reply $rid 5000
        $val = $reply.result.result.value
        if ($val -and $val -like "OK:*") {
            $result = "OK"; $detectedPrice = $val.Replace("OK:", ""); break
        } elseif ($val -and $val -like "ERR:*") {
            $result = $val; break
        }
    }

    if ($result -eq "OK") {
        Write-Host "OK (Preis: $detectedPrice)" -ForegroundColor Green; $Success++
    } else {
        Write-Host "FEHLER ($result)" -ForegroundColor Red; $Fail++
    }
    Send-Cdp "Target.closeTarget" @{ targetId = $tid } | Out-Null
}

Write-Host "`nErgebnis: $Success OK / $Fail Fehler"
if ($Success -gt 0 -or $Fail -gt 0) {
    Write-Host "`nÖffne Warenkorb..."
    $arMain = Wait-Reply (Send-Cdp "Target.attachToTarget" @{ targetId = $mainTid; flatten = $true })
    Send-Cdp "Page.navigate" @{ url = "https://bandcamp.com/cart" } $arMain.result.sessionId | Out-Null
    Send-Cdp "Target.activateTarget" @{ targetId = $mainTid } | Out-Null
} else {
    Send-Cdp "Target.closeTarget" @{ targetId = $mainTid } | Out-Null
}
Read-Host "`nFertig. Enter zum Beenden"
