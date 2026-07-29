# run-cdp.ps1 — Launch Obsidian with CDP for remote debugging
# Run as Administrator (required for firewall + portproxy)
# Usage: .\run-cdp.ps1 <vault-path> [port]

param(
    [Parameter(Mandatory=$true)]
    [string]$Vault,
    [int]$Port = 9222
)

$ErrorActionPreference = "Stop"

# ── Admin check ──────────────────────────────────────────────────────
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "[ERROR] Run as Administrator!" -ForegroundColor Red
    Write-Host "  powershell -Command Start-Process powershell -Verb RunAs -ArgumentList '-File','$PSCommandPath','$Vault','$Port'"
    exit 1
}

# ── Find Obsidian ────────────────────────────────────────────────────
$Obsidian = $null
$candidates = @(
    "$env:LOCALAPPDATA\Obsidian\Obsidian.exe",
    "$env:LOCALAPPDATA\obsidian\Obsidian.exe",
    "$env:APPDATA\Obsidian\Obsidian.exe"
)
foreach ($p in $candidates) {
    if (Test-Path $p) { $Obsidian = $p; break }
}
if (-not $Obsidian) {
    Write-Host "[ERROR] Obsidian.exe not found. Checked:" -ForegroundColor Red
    $candidates | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "[OK] Found: $Obsidian"

# ── Kill existing Obsidian ───────────────────────────────────────────
$running = Get-Process -Name "Obsidian" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "[INFO] Killing running Obsidian..."
    $running | Stop-Process -Force
    Start-Sleep -Seconds 3
}

# ── Create vault if needed ───────────────────────────────────────────
if (-not (Test-Path $Vault)) {
    Write-Host "[INFO] Creating vault directory: $Vault"
    New-Item -ItemType Directory -Path $Vault -Force | Out-Null
}

# ── Detect local IP ──────────────────────────────────────────────────
$LocalIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -notmatch '^127|^169'
} | Select-Object -First 1).IPAddress
if (-not $LocalIP) {
    $LocalIP = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null } |
        Select-Object -First 1).IPv4Address.IPAddress
}
if (-not $LocalIP) { $LocalIP = "UNKNOWN" }

# ── Firewall ─────────────────────────────────────────────────────────
Write-Host "[INFO] Adding firewall rule for port $Port..."
netsh advfirewall firewall delete rule name="Obsidian CDP" >$null 2>&1
netsh advfirewall firewall add rule name="Obsidian CDP" dir=in action=allow protocol=TCP localport=$Port >$null 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Firewall rule added"
} else {
    Write-Host "[WARN] Could not add firewall rule"
}

# ── Port proxy ───────────────────────────────────────────────────────
Write-Host "[INFO] Setting up port proxy..."
netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 >$null 2>&1
netsh interface portproxy add v4tov4 listenport=$Port listenaddress=0.0.0.0 connectport=$Port connectaddress=127.0.0.1 >$null 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Port proxy: 0.0.0.0:$Port -> 127.0.0.1:$Port"
} else {
    Write-Host "[WARN] Could not add port proxy"
}

# ── Launch Obsidian ──────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Launching Obsidian with CDP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Vault:  $Vault"
Write-Host "  Port:   $Port"
Write-Host "  IP:     $LocalIP"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$proc = Start-Process -FilePath $Obsidian -ArgumentList @(
    "--remote-debugging-port=$Port",
    "--remote-debugging-address=0.0.0.0",
    "--remote-allow-origins=*",
    $Vault
) -PassThru

# ── Wait for CDP to become available ─────────────────────────────────
Write-Host "[INFO] Waiting for CDP to come online..."
$maxWait = 30
for ($i = 0; $i -lt $maxWait; $i++) {
    Start-Sleep -Seconds 1
    try {
        $result = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json" -TimeoutSec 2 -UseBasicParsing
        if ($result.StatusCode -eq 200 -and $result.Content) {
            Write-Host "[OK] CDP listening on 127.0.0.1:$Port" -ForegroundColor Green
            Write-Host ""
            Write-Host "Remote dev machine:" -ForegroundColor Yellow
            Write-Host "  CDP_HOST=$LocalIP python3 cdp-eval.py '1 + 1'"
            Write-Host "  CDP_HOST=$LocalIP python3 cdp-screenshot.py"
            Write-Host ""
            Write-Host "Obsidian running (PID: $($proc.Id)). Close this window or press Ctrl+C to stop."
            # Keep running until user presses Ctrl+C
            Wait-Process -Id $proc.Id
            exit 0
        }
    } catch {
        # Not ready yet
    }
    Write-Host -NoNewline "."
}

Write-Host ""
Write-Host "[ERROR] CDP did not start within ${maxWait}s" -ForegroundColor Red
Write-Host "Check http://127.0.0.1:$Port/json manually"

# ── Cleanup on exit ──────────────────────────────────────────────────
netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 >$null 2>&1
netsh advfirewall firewall delete rule name="Obsidian CDP" >$null 2>&1
