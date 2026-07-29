# test-cdp-local.ps1 — Test Obsidian CDP locally and report results
# Usage: .\test-cdp-local.ps1

$ErrorActionPreference = "Stop"
$Port = 9222

Write-Host "=== CDP Local Test ===" -ForegroundColor Cyan

# 1. Check process
Write-Host "`n1. Obsidian process:" -ForegroundColor Yellow
$obsidian = Get-Process -Name "Obsidian" -ErrorAction SilentlyContinue
if ($obsidian) {
    Write-Host "   [OK] Obsidian running (PID: $($obsidian.Id), Started: $($obsidian.StartTime))"
} else {
    Write-Host "   [FAIL] Obsidian NOT running"
}

# 2. Check port
Write-Host "`n2. Port $Port listening:" -ForegroundColor Yellow
$netstat = netstat -ano | Select-String ":$Port "
if ($netstat) {
    Write-Host "   [OK] Port listening:"
    $netstat | ForEach-Object { Write-Host "   $_" }
} else {
    Write-Host "   [FAIL] Port $Port NOT listening"
}

# 3. Check CDP HTTP
Write-Host "`n3. CDP HTTP endpoint:" -ForegroundColor Yellow
try {
    $result = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json" -TimeoutSec 5 -UseBasicParsing
    Write-Host "   [OK] Got $($result.Content.Length) bytes"
    $targets = $result.Content | ConvertFrom-Json
    Write-Host "   Targets: $($targets.Count)"
    foreach ($t in $targets) {
        Write-Host "     - $($t.type): $($t.title)  =>  $($t.webSocketDebuggerUrl)"
    }
} catch {
    Write-Host "   [FAIL] $_"
}

# 4. Try CDP eval via WebSocket
Write-Host "`n4. CDP WebSocket eval:" -ForegroundColor Yellow
try {
    $targets = (Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json" -TimeoutSec 5 -UseBasicParsing).Content | ConvertFrom-Json
    $pages = $targets | Where-Object { $_.type -eq "page" -and $_.url -like "*obsidian*" }
    if (-not $pages) { $pages = $targets | Where-Object { $_.type -eq "page" } }
    if (-not $pages) { throw "No page targets" }

    $wsUrl = $pages[0].webSocketDebuggerUrl
    Write-Host "   Connecting to: $wsUrl"

    # Use .NET WebSocket
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ct = New-Object System.Threading.CancellationToken
    $ws.ConnectAsync([Uri]$wsUrl, $ct).Wait(10000)

    # Send Runtime.evaluate
    $msg = '{"id":1,"method":"Runtime.evaluate","params":{"expression":"app.commands.commands[''terminal:open''].name + '' | '' + navigator.platform + '' | vault: '' + (app.vault.getName?.() ?? ''unknown'')","returnByValue":true,"awaitPromise":true}}'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $segment = [ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait(5000)

    # Receive response
    $buffer = [byte[]]::new(4096)
    $recvSegment = [ArraySegment[byte]]::new($buffer)
    $result = $ws.ReceiveAsync($recvSegment, $ct).Result
    $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)

    Write-Host "   [OK] JS result: $response"
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait(3000)
} catch {
    Write-Host "   [FAIL] $_"
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
