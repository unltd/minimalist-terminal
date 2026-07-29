# debug.ps1 — Single entry point for Obsidian CDP debugging setup
# ============================================================================
# Handles: kill Obsidian → launch with CDP → firewall → portproxy → verify
# Each step is verified with [OK] / [FAIL] and clear error messages.
#
# Usage:
#   .\debug.ps1 <vault-path> [-Port 9222] [-NoSetup] [-Test]
#
#   vault-path     Path to Obsidian vault (required)
#   -Port N        CDP port (default 9222)
#   -NoSetup       Skip firewall+portproxy (just launch Obsidian with CDP)
#   -Test          Run local CDP self-test after setup
#
# Examples:
#   .\debug.ps1 C:\Users\tania\Documents\obsidian-test
#   .\debug.ps1 C:\vault -Port 9223 -Test
# ============================================================================

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Vault,
    [int]$Port = 9222,
    [switch]$NoSetup,
    [switch]$Test
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── Colors ───────────────────────────────────────────────────────────
function Write-Step  { Write-Host "`n>>> $args" -ForegroundColor Cyan }
function Write-OK    { Write-Host "    [OK] $args" -ForegroundColor Green }
function Write-FAIL  { Write-Host "    [FAIL] $args" -ForegroundColor Red }
function Write-WARN  { Write-Host "    [WARN] $args" -ForegroundColor Yellow }
function Write-INFO  { Write-Host "    $args" }

# ══════════════════════════════════════════════════════════════════════
# Step 1: Admin check
# ══════════════════════════════════════════════════════════════════════
Write-Step "Step 1/6: Administrator privileges"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin -and -not $NoSetup) {
    Write-WARN "Not running as Administrator."
    Write-INFO "Firewall + portproxy require Admin rights."
    Write-INFO "Relaunching as Administrator..."
    $args = "-File `"$PSCommandPath`" `"$Vault`" -Port $Port"
    if ($Test) { $args += " -Test" }
    Start-Process powershell -Verb RunAs -ArgumentList $args
    exit 0
}

if ($isAdmin) {
    Write-OK "Running as Administrator"
} else {
    Write-INFO "Running as user (--NoSetup mode — skipping firewall/portproxy)"
}

# ══════════════════════════════════════════════════════════════════════
# Step 2: Kill existing Obsidian
# ══════════════════════════════════════════════════════════════════════
Write-Step "Step 2/6: Stopping existing Obsidian"

$killed = $false
$obsidianProcs = Get-Process -Name "Obsidian" -ErrorAction SilentlyContinue
if ($obsidianProcs) {
    Write-INFO "Found $($obsidianProcs.Count) Obsidian process(es)"
    $obsidianProcs | ForEach-Object { Write-INFO "  PID $($_.Id) — Started $($_.StartTime)" }
    try {
        $obsidianProcs | Stop-Process -Force -ErrorAction Stop
        Write-OK "Killed $($obsidianProcs.Count) process(es)"
        $killed = $true
    } catch {
        Write-FAIL "Could not kill: $_"
        exit 1
    }
} else {
    Write-OK "No Obsidian processes found"
}

if ($killed) {
    Write-INFO "Waiting 3s for cleanup..."
    Start-Sleep -Seconds 3
}

# ══════════════════════════════════════════════════════════════════════
# Step 3: Find Obsidian.exe
# ══════════════════════════════════════════════════════════════════════
Write-Step "Step 3/6: Locating Obsidian.exe"

$ObsidianExe = $null
$candidates = @(
    "$env:LOCALAPPDATA\Obsidian\Obsidian.exe",
    "$env:LOCALAPPDATA\obsidian\Obsidian.exe",
    "$env:APPDATA\Obsidian\Obsidian.exe"
)
foreach ($p in $candidates) {
    if (Test-Path $p) {
        $ObsidianExe = $p
        Write-OK "Found: $ObsidianExe"
        break
    }
}
if (-not $ObsidianExe) {
    Write-FAIL "Obsidian.exe not found. Checked:"
    $candidates | ForEach-Object { Write-INFO "  $_" }
    Write-INFO "Install Obsidian from https://obsidian.md/download"
    exit 1
}

# ══════════════════════════════════════════════════════════════════════
# Step 4: Verify / create vault
# ══════════════════════════════════════════════════════════════════════
Write-Step "Step 4/6: Verifying vault"

if (-not (Test-Path $Vault)) {
    Write-WARN "Vault not found: $Vault"
    Write-INFO "Creating directory..."
    try {
        New-Item -ItemType Directory -Path $Vault -Force | Out-Null
        Write-OK "Created vault directory"
    } catch {
        Write-FAIL "Cannot create vault: $_"
        exit 1
    }
} else {
    Write-OK "Vault exists: $Vault"
}

# ══════════════════════════════════════════════════════════════════════
# Step 5: Launch Obsidian with CDP
# ══════════════════════════════════════════════════════════════════════
Write-Step "Step 5/6: Launching Obsidian with CDP"

# Double-check no stale process
$stale = Get-Process -Name "Obsidian" -ErrorAction SilentlyContinue
if ($stale) {
    Write-WARN "Obsidian still running — force killing..."
    $stale | Stop-Process -Force
    Start-Sleep -Seconds 2
}

Write-INFO "Command: $ObsidianExe --remote-debugging-port=$Port --remote-allow-origins=* `"$Vault`""

$proc = Start-Process -FilePath $ObsidianExe -ArgumentList @(
    "--remote-debugging-port=$Port",
    "--remote-debugging-address=0.0.0.0",
    "--remote-allow-origins=*",
    $Vault
) -PassThru

Write-OK "Obsidian launched (PID: $($proc.Id))"

# Wait for CDP to come online
Write-INFO "Waiting for CDP on 127.0.0.1:$Port ..."
$cdpReady = $false
$maxWait = 30
for ($i = 1; $i -le $maxWait; $i++) {
    Write-Host -NoNewline "."
    Start-Sleep -Seconds 1
    try {
        $check = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json" -TimeoutSec 2 -UseBasicParsing
        if ($check.StatusCode -eq 200 -and $check.Content) {
            $cdpReady = $true
            break
        }
    } catch {
        # Not ready yet
    }
}
Write-Host ""

if ($cdpReady) {
    Write-OK "CDP listening on 127.0.0.1:$Port (took ${i}s)"
} else {
    Write-FAIL "CDP did not start within ${maxWait}s"
    Write-INFO "Try manually:"
    Write-INFO "  1. Check Obsidian is running: Get-Process Obsidian"
    Write-INFO "  2. Check port: netstat -ano | findstr $Port"
    Write-INFO "  3. Check http://127.0.0.1:$Port/json in browser"
    if (-not $NoSetup) {
        Write-INFO ""
        Write-INFO "Network setup will continue (CDP may start later)..."
    } else {
        exit 1
    }
}

# ══════════════════════════════════════════════════════════════════════
# Step 6: Network setup (firewall + portproxy)
# ══════════════════════════════════════════════════════════════════════
if (-not $NoSetup) {
    Write-Step "Step 6/6: Network setup (firewall + portproxy)"

    # Detect local IP
    $LocalIP = $null
    try {
        $LocalIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.IPAddress -notmatch '^127|^169'
        } | Select-Object -First 1).IPAddress
    } catch {}
    if (-not $LocalIP) {
        try {
            $LocalIP = (Get-NetIPConfiguration | Where-Object {
                $_.IPv4DefaultGateway -ne $null
            } | Select-Object -First 1).IPv4Address.IPAddress
        } catch {}
    }
    if (-not $LocalIP) { $LocalIP = "DETECT_FAILED" }

    # Firewall
    Write-INFO "Adding firewall rule..."
    $null = netsh advfirewall firewall delete rule name="Obsidian CDP" 2>&1
    $result = netsh advfirewall firewall add rule name="Obsidian CDP" dir=in action=allow protocol=TCP localport=$Port 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Firewall rule added for port $Port"
    } else {
        Write-WARN "Could not add firewall rule (error: $result)"
    }

    # Port proxy
    Write-INFO "Adding port proxy..."
    $null = netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 2>&1
    $result = netsh interface portproxy add v4tov4 listenport=$Port listenaddress=0.0.0.0 connectport=$Port connectaddress=127.0.0.1 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Port proxy: 0.0.0.0:$Port -> 127.0.0.1:$Port"
    } else {
        Write-WARN "Could not add port proxy (error: $result)"
    }

    # Verify port is accessible
    Write-INFO "Verifying port accessibility..."
    $netstat = netstat -ano | Select-String ":$Port "
    if ($netstat) {
        Write-OK "Port $Port confirmed in netstat:"
        $netstat | ForEach-Object { Write-INFO "  $_" }
    } else {
        Write-WARN "Port $Port not in netstat (may be normal if using portproxy)"
    }
}

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Obsidian CDP — Ready" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Vault:    $Vault"
Write-Host "  Port:     $Port"
Write-Host "  CDP:      $($cdpReady ? 'ONLINE' : 'WAITING')"
Write-Host "  Local IP: $LocalIP"
Write-Host "  PID:      $($proc.Id)"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Remote dev machine commands:" -ForegroundColor Yellow
Write-Host "  CDP_HOST=$LocalIP python3 debug.py test"
Write-Host "  CDP_HOST=$LocalIP python3 debug.py screenshot"
Write-Host "  CDP_HOST=$LocalIP python3 debug.py eval '<javascript>'"
Write-Host ""
Write-Host "Local test:" -ForegroundColor Yellow
Write-Host "  python3 debug.py test --local"
Write-Host ""
Write-Host "Press Ctrl+C to stop Obsidian and cleanup" -ForegroundColor DarkGray
Write-Host "(firewall + portproxy will be removed on exit)"

# ══════════════════════════════════════════════════════════════════════
# Self-test (optional)
# ══════════════════════════════════════════════════════════════════════
if ($Test -and $cdpReady) {
    Write-Step "Self-test: CDP evaluation"
    try {
        $targets = (Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json" -UseBasicParsing).Content | ConvertFrom-Json
        $pages = $targets | Where-Object { $_.type -eq "page" -and $_.url -like "*obsidian*" }
        if (-not $pages) { $pages = $targets | Where-Object { $_.type -eq "page" } }
        if ($pages) {
            Write-OK "Found $($pages.Count) Obsidian page(s)"
            Write-INFO "Title: $($pages[0].title)"
            Write-INFO "URL: $($pages[0].url)"
        } else {
            Write-WARN "No Obsidian pages found in CDP targets"
        }
    } catch {
        Write-FAIL "Self-test failed: $_"
    }
}

# ══════════════════════════════════════════════════════════════════════
# Wait & cleanup
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "Obsidian is running. Close this window to stop." -ForegroundColor DarkGray

try {
    Wait-Process -Id $proc.Id -ErrorAction Stop
} catch {
    # User closed window or killed process
}

# Cleanup
if (-not $NoSetup) {
    Write-Host "Cleaning up..." -ForegroundColor DarkGray
    $null = netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 2>&1
    $null = netsh advfirewall firewall delete rule name="Obsidian CDP" 2>&1
    Write-Host "Firewall + portproxy removed." -ForegroundColor DarkGray
}
