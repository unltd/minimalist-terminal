@echo off
setlocal enabledelayedexpansion
REM ===========================================================================
REM run-cdp.bat — Launch Obsidian in CDP (Chrome DevTools Protocol) mode
REM for remote debugging from another machine on the home network.
REM
REM Usage:
REM   run-cdp.bat                    Launch with default vault (%%USERPROFILE%%\obsidian-test)
REM   run-cdp.bat C:\path\to\vault   Launch with specific vault
REM   run-cdp.bat 9222               Launch with specific port
REM   run-cdp.bat C:\vault 9222      Launch with specific vault + port
REM
REM From your dev machine (Mac/Linux), connect via CDP scripts:
REM   CDP_HOST=<this-machine-ip> python3 scripts/cdp-eval.py '<js>'
REM   CDP_HOST=<this-machine-ip> python3 scripts/cdp-screenshot.py
REM ===========================================================================

REM ── Parse arguments ──────────────────────────────────────────────────────
set VAULT=%USERPROFILE%\obsidian-test
set PORT=9222

if not "%~1"=="" (
    REM Check if arg1 is a number (port)
    echo %~1| findstr /r "^[0-9][0-9]*$" >nul
    if !errorlevel!==0 (
        set PORT=%~1
    ) else (
        set VAULT=%~1
    )
)
if not "%~2"=="" (
    echo %~2| findstr /r "^[0-9][0-9]*$" >nul
    if !errorlevel!==0 set PORT=%~2
)

REM ── Find Obsidian.exe ────────────────────────────────────────────────────
set OBSIDIAN=
for %%p in (
    "%LOCALAPPDATA%\Obsidian\Obsidian.exe"
    "%LOCALAPPDATA%\obsidian\Obsidian.exe"
    "%APPDATA%\Obsidian\Obsidian.exe"
) do (
    if exist %%p (
        set OBSIDIAN=%%~p
        goto :found
    )
)
:found

if "%OBSIDIAN%"=="" (
    echo [ERROR] Obsidian.exe not found.
    echo Checked: %%LOCALAPPDATA%%\Obsidian, %%APPDATA%%\Obsidian
    echo.
    echo Please edit this script and set OBSIDIAN path manually.
    pause
    exit /b 1
)

echo [OK] Found: %OBSIDIAN%

REM ── Check for already-running Obsidian ───────────────────────────────────
tasklist /fi "imagename eq Obsidian.exe" 2>nul | find /i "Obsidian.exe" >nul
if !errorlevel!==0 (
    echo.
    echo [WARNING] Obsidian is already running!
    echo CDP flags only take effect on FIRST launch. The running instance
    echo does NOT have --remote-debugging-port enabled.
    echo.
    choice /c yn /m "Close running Obsidian and re-launch"
    if !errorlevel!==2 exit /b 1
    echo Killing Obsidian...
    taskkill /f /im Obsidian.exe >nul 2>&1
    timeout /t 2 /nobreak >nul
)

REM ── Verify vault exists ──────────────────────────────────────────────────
if not exist "%VAULT%" (
    echo [WARNING] Vault directory does not exist: %VAULT%
    echo Creating it...
    mkdir "%VAULT%"
)

REM ── Detect local IP ──────────────────────────────────────────────────────
set LOCAL_IP=

REM Method 1: PowerShell one-liner — locale-independent, finds the primary IP.
REM Uses a simplified command with minimal special chars to avoid escaping issues.
for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "((Get-NetIPAddress -AddressFamily IPv4).IPAddress -notmatch '^127|^169' | Select-Object -First 1) -replace ' .*'" 2^>nul`) do (
    set IP=%%a
    if not "!IP!"=="" set LOCAL_IP=!IP!
)

REM Method 2: ipconfig — scans output for any line containing an IPv4-like pattern.
REM Uses findstr with /R (regex) to match x.x.x.x regardless of locale.
if "%LOCAL_IP%"=="" (
    for /f "tokens=*" %%L in ('ipconfig ^| findstr /R "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"') do (
        for /f "tokens=2 delims=:" %%a in ("%%L") do (
            for /f "tokens=1 delims= " %%b in ("%%a") do (
                set IP=%%b
                set IP=!IP: =!
                REM Skip loopback and APIPA
                echo !IP! | findstr /B "127. 169.254." >nul
                if !errorlevel!==1 if "!LOCAL_IP!"=="" set LOCAL_IP=!IP!
            )
        )
    )
)

REM Last resort
if "%LOCAL_IP%"=="" (
    echo [WARN] Could not detect local IP address.
    echo        Check your network connection or edit run-cdp.bat and set LOCAL_IP manually.
    set LOCAL_IP=YOUR_IP_HERE
)

REM ── Firewall hint ────────────────────────────────────────────────────────
netsh advfirewall firewall show rule name="Obsidian CDP" >nul 2>&1
if !errorlevel!==1 (
    echo.
    echo [WARNING] Firewall rule "Obsidian CDP" not found.
    echo Run this command as Administrator to allow incoming CDP connections:
    echo.
    echo   netsh advfirewall firewall add rule name="Obsidian CDP" dir=in action=allow protocol=TCP localport=%PORT%
    echo.
)

REM ── Launch Obsidian ──────────────────────────────────────────────────────
echo ========================================
echo   Obsidian CDP Mode
echo ========================================
echo   Vault:  %VAULT%
echo   Port:   %PORT%
echo   This PC IP: %LOCAL_IP%
echo ========================================
echo.
echo Starting Obsidian...
echo.

REM Launch with CDP flags.
REM --remote-debugging-address=0.0.0.0 tells Electron to bind to all
REM interfaces (not just 127.0.0.1). May not work on all Electron versions;
REM portproxy below handles the fallback.
start "" "%OBSIDIAN%" ^
    --remote-debugging-port=%PORT% ^
    --remote-debugging-address=0.0.0.0 ^
    --remote-allow-origins=* ^
    "%VAULT%"

REM Give Obsidian a moment to start
timeout /t 4 /nobreak >nul

REM Verify CDP is listening locally
set CDP_LOCAL_OK=0
curl -s http://127.0.0.1:%PORT%/json >nul 2>&1
if !errorlevel!==0 (
    echo [OK] CDP listening on 127.0.0.1:%PORT%
    set CDP_LOCAL_OK=1
) else (
    echo [WARN] CDP not responding on 127.0.0.1:%PORT% — Obsidian may still be starting
    echo        Try: curl http://127.0.0.1:%PORT%/json
)

REM ── Open CDP to the network ────────────────────────────────────────────
echo.
echo [SETUP] Opening port %PORT% for remote access...

REM Firewall rule
netsh advfirewall firewall add rule name="Obsidian CDP" dir=in action=allow protocol=TCP localport=%PORT% >nul 2>&1
if !errorlevel!==0 (
    echo [OK] Firewall rule added for port %PORT%
) else (
    echo [WARN] Could not add firewall rule ^(not running as Admin?^)
    echo        Run manually as Administrator:
    echo        netsh advfirewall firewall add rule name="Obsidian CDP" dir=in action=allow protocol=TCP localport=%PORT%
)

REM Port proxy — forwards 0.0.0.0:%PORT% to 127.0.0.1:%PORT%
REM Remove any stale rule first, then add fresh
netsh interface portproxy delete v4tov4 listenport=%PORT% listenaddress=0.0.0.0 >nul 2>&1
netsh interface portproxy add v4tov4 listenport=%PORT% listenaddress=0.0.0.0 connectport=%PORT% connectaddress=127.0.0.1 >nul 2>&1
if !errorlevel!==0 (
    echo [OK] Port proxy: 0.0.0.0:%PORT% → 127.0.0.1:%PORT%
) else (
    echo [WARN] Could not add port proxy ^(not running as Admin?^)
    echo        Run manually as Administrator:
    echo        netsh interface portproxy add v4tov4 listenport=%PORT% listenaddress=0.0.0.0 connectport=%PORT% connectaddress=127.0.0.1
)

echo.
echo ========================================
echo   Remote dev machine commands:
echo ========================================
echo   CDP_HOST=%LOCAL_IP% python3 cdp/cdp-eval.py "1 + 1"
echo   CDP_HOST=%LOCAL_IP% python3 cdp/cdp-screenshot.py
echo ========================================
echo.
echo Press Ctrl+C or close this window to stop Obsidian...

REM ── Wait & cleanup ─────────────────────────────────────────────────────
pause >nul
echo.

REM Cleanup port proxy
netsh interface portproxy delete v4tov4 listenport=%PORT% listenaddress=0.0.0.0 >nul 2>&1
echo [OK] Port proxy removed

REM Cleanup firewall rule
netsh advfirewall firewall delete rule name="Obsidian CDP" >nul 2>&1

choice /c yn /m "Kill Obsidian"
if !errorlevel!==1 taskkill /f /im Obsidian.exe >nul 2>&1
