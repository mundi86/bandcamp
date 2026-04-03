#!/usr/bin/env pwsh
# Bandcamp Auto-Cart (Single-Window Price Edition)
# Keine Installation nötig - nur Chrome/Edge + PowerShell.

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LinkFile = Join-Path $ScriptDir "bandcamp.txt"
$DebugPort = 9222
$ProfileDir = Join-Path $env:TEMP "bc-cart-profile-std"

# --- URLs laden ---
if (-not (Test-Path $LinkFile)) {
    Write-Host "FEHLER: bandcamp.txt fehlt!" -ForegroundColor Red
    exit 1
}

$Urls = @(Get-Content $LinkFile | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") })
if ($Urls.Count -eq 0) {
    Write-Host "FEHLER: Keine URLs!" -ForegroundColor Red
    exit 1
}

# --- Browser finden ---
$BrowserPath = $null
@(
    "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LocalAppData\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
) | ForEach-Object {
    if (-not $BrowserPath -and (Test-Path $_)) {
        $BrowserPath = $_
    }
}

if (-not $BrowserPath) {
    Write-Host "FEHLER: Kein kompatibler Chrome/Edge-Browser gefunden!" -ForegroundColor Red
    exit 1
}

# --- CDP via WebSocket ---
$script:CdpMsgId = 1000
$script:Ws = $null

function Connect-Cdp {
    $versionInfo = Invoke-RestMethod "http://127.0.0.1:$DebugPort/json/version" -TimeoutSec 5
    $socket = [System.Net.WebSockets.ClientWebSocket]::new()
    $socket.ConnectAsync([Uri]$versionInfo.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    $script:Ws = $socket
}

function Send-Cdp([string]$Method, [hashtable]$Params = @{}, [string]$SessionId = "") {
    $script:CdpMsgId++
    $id = $script:CdpMsgId
    $message = @{ id = $id; method = $Method; params = $Params }
    if ($SessionId) {
        $message.sessionId = $SessionId
    }

    $json = $message | ConvertTo-Json -Compress -Depth 10
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $segment = [ArraySegment[byte]]::new($bytes)
    $script:Ws.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    return $id
}

function Wait-Reply([int]$TargetId, [int]$TimeoutMs = 15000) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $fullMessage = ""
        $isEnd = $false

        do {
            $buffer = New-Object byte[] 262144
            $cts = [Threading.CancellationTokenSource]::new(3000)
            try {
                $segment = [ArraySegment[byte]]::new($buffer)
                $result = $script:Ws.ReceiveAsync($segment, $cts.Token).GetAwaiter().GetResult()
                $fullMessage += [Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
                $isEnd = $result.EndOfMessage
            } catch {
                $isEnd = $true
                break
            } finally {
                $cts.Dispose()
            }
        } while (-not $isEnd)

        if ($fullMessage) {
            $obj = $fullMessage | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($obj -and $obj.id -eq $TargetId) {
                return $obj
            }
        }
    }

    return $null
}

# --- START ---
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Bandcamp -> Warenkorb (Perfect Price)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$portOpen = $false
try {
    [void](Invoke-RestMethod "http://127.0.0.1:$DebugPort/json/version" -TimeoutSec 1)
    $portOpen = $true
} catch {}

if (-not $portOpen) {
    # Wir starten einen separaten Browser mit Debug-Port, damit die Session stabil und reproduzierbar bleibt.
    Start-Process -FilePath $BrowserPath -ArgumentList @(
        "--remote-debugging-port=$DebugPort",
        "--user-data-dir=$ProfileDir",
        "--no-first-run",
        "--no-default-browser-check",
        "about:blank"
    ) | Out-Null
    Start-Sleep -Seconds 3
}

try {
    Connect-Cdp
} catch {
    Write-Host "FEHLER: Browser-Verbindung fehlgeschlagen." -ForegroundColor Red
    exit 1
}

# Der erste offene Target-Tab dient als Anchor, auf den wir am Ende den Warenkorb navigieren.
$targets = Invoke-RestMethod "http://127.0.0.1:$DebugPort/json/list"
if (-not $targets -or $targets.Count -eq 0) {
    Write-Host "FEHLER: Kein Browser-Tab fuer den Anchor gefunden." -ForegroundColor Red
    exit 1
}
$mainTid = $targets[0].id

$Success = 0
$Fail = 0
$CartCount = 0

for ($i = 0; $i -lt $Urls.Count; $i++) {
    $url = $Urls[$i].Trim()
    $num = $i + 1
    $label = ($url -split "/" | Where-Object { $_ })[-1]
    if (-not $label) {
        $label = $url
    }

    Write-Host "[$num/$($Urls.Count)] $label ... " -NoNewline

    $tid = $null
    try {
        $created = Wait-Reply (Send-Cdp "Target.createTarget" @{ url = "about:blank" })
        if (-not $created) { throw "Target.createTarget Timeout" }
        $tid = $created.result.targetId

        $attached = Wait-Reply (Send-Cdp "Target.attachToTarget" @{ targetId = $tid; flatten = $true })
        if (-not $attached) { throw "Target.attachToTarget Timeout" }
        $sid = $attached.result.sessionId

        [void](Wait-Reply (Send-Cdp "Runtime.enable" @{} $sid) 5000)
        [void](Wait-Reply (Send-Cdp "Page.navigate" @{ url = $url } $sid) 5000)

        $result = "TIMEOUT"
        $detectedPrice = "0.00"
        $sw = [Diagnostics.Stopwatch]::StartNew()

        while ($sw.ElapsedMilliseconds -lt 20000) {
            Start-Sleep -Milliseconds 1000
            $js = @"
(async () => {
    try {
        const getPrice = () => {
            // Bandcamp rendert den Zielpreis nicht konsistent im selben Feld.
            if (window.TralbumData) {
                const td = window.TralbumData;
                if (td.current && td.current.minimum_price != null) return td.current.minimum_price;
                if (td.minimum_price_nonzero != null) return td.minimum_price_nonzero;
                if (td.minimum_price != null) return td.minimum_price;
                if (td.current && td.current.price != null) return td.current.price;
            }
            const el = document.querySelector('[data-tralbum]');
            if (el) {
                const data = JSON.parse(el.getAttribute('data-tralbum'));
                if (data.current && data.current.minimum_price != null) return data.current.minimum_price;
                if (data.minimum_price_nonzero != null) return data.minimum_price_nonzero;
                if (data.minimum_price != null) return data.minimum_price;
                if (data.current && data.current.price != null) return data.current.price;
            }
            const ldEl = document.querySelector('script[type="application/ld+json"]');
            if (ldEl) {
                const ld = JSON.parse(ldEl.innerText);
                const offer = Array.isArray(ld.offers) ? ld.offers[0] : ld.offers;
                if (offer && offer.price != null) return parseFloat(offer.price);
            }
            return 0;
        };
        const getID = () => {
            if (window.TralbumData) return window.TralbumData.id;
            const el = document.querySelector('[data-tralbum]');
            if (el) return JSON.parse(el.getAttribute('data-tralbum')).id;
            const idEl = document.querySelector('[data-item-id]');
            if (idEl) return idEl.getAttribute('data-item-id');
            return null;
        };
        const id = getID();
        const price = getPrice();
        if (!id) return null;

        // sync_num und cart_length spiegeln den lokalen Zustand an die Cart-API zurueck.
        const type = window.location.href.includes('/album/') ? 'a' : 't';
        const res = await fetch(window.location.origin + '/cart/cb', {
            method: 'POST',
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'req=add&item_type=' + type + '&item_id=' + id + '&unit_price=' + price + '&quantity=1&local_id=lc' + Date.now() + '&sync_num=$num&cart_length=$CartCount'
        });
        const d = await res.json();
        if (d && (d.id || d.resync === true || d.ok === true)) return 'OK:' + price;
        return 'ERR:' + JSON.stringify(d);
    } catch (e) {
        return 'ERR:' + e.message;
    }
})()
"@

            $rid = Send-Cdp "Runtime.evaluate" @{ expression = $js; awaitPromise = $true; returnByValue = $true } $sid
            $reply = Wait-Reply $rid 5000
            $val = $reply.result.result.value

            if ($val -and $val -like "OK:*") {
                $result = "OK"
                $detectedPrice = $val.Replace("OK:", "")
                break
            }
            if ($val -and $val -like "ERR:*") {
                $result = $val
                break
            }
        }

        if ($result -eq "OK") {
            Write-Host "OK (Preis: $detectedPrice)" -ForegroundColor Green
            $Success++
            $CartCount++
        } else {
            Write-Host "FEHLER ($result)" -ForegroundColor Red
            $Fail++
        }
    } catch {
        Write-Host "FEHLER ($($_.Exception.Message))" -ForegroundColor Red
        $Fail++
    } finally {
        if ($tid) {
            Send-Cdp "Target.closeTarget" @{ targetId = $tid } | Out-Null
        }
    }
}

Write-Host "`nErgebnis: $Success OK / $Fail Fehler"
if ($Success -gt 0 -or $Fail -gt 0) {
    Write-Host "`nOeffne Warenkorb..."
    $anchor = Wait-Reply (Send-Cdp "Target.attachToTarget" @{ targetId = $mainTid; flatten = $true })
    if ($anchor) {
        Send-Cdp "Page.navigate" @{ url = "https://bandcamp.com/cart" } $anchor.result.sessionId | Out-Null
        Send-Cdp "Target.activateTarget" @{ targetId = $mainTid } | Out-Null
        Start-Sleep -Seconds 2
    }
}

Write-Host "`nFertig. Browser bleibt fuer Checkout offen."
Read-Host "Enter zum Beenden des Scripts (Browser bleibt offen)"
