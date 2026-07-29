@echo off
setlocal enabledelayedexpansion
title Obsidian CDP Debug

:: ===========================================================================
:: debug.bat — Single entry point for Obsidian CDP debugging on Windows
::
:: Usage:
::   debug.bat <vault-path> [port]
::   debug.bat C:\Users\tania\Documents\obsidian-test
::   debug.bat C:\vault 9223
::
:: Does:
::   1. Admin check (with auto-relaunch)
::   2. Kill existing Obsidian
::   3. Launch with --remote-debugging-port
::   4. Wait for CDP (30s with progress dots)
::   5. Setup firewall + portproxy
::   6. Detect IP + show remote commands
::   7. Self-test (optional)
::
:: Every step logged with [OK] / [FAIL] / [WARN].
:: ===========================================================================

set VAULT=%~1
set PORT=%~2
if "%PORT%"=="" set PORT=9222

if "%VAULT%"=="" (
    echo Usage: debug.bat ^<vault-path^> [port]
    echo   debug.bat C:\Users\tania\Documents\obsidian-test
    exit /b 1
)

:: ── Validate vault path ─────────────────────────────────────────────
if not exist "%VAULT%" (
    echo [WARN] Vault not found: %VAULT%
    echo [INFO] Creating directory...
    mkdir "%VAULT%" 2>nul
    if errorlevel 1 (
        echo [FAIL] Cannot create vault directory
        pause
        exit /b 1
    )
    echo [OK] Created vault directory
)

:: ── Self-elevate to admin ───────────────────────────────────────────
net session >nul 2>&1
if errorlevel 1 (
    echo [WARN] Not running as Administrator.
    echo [INFO] Firewall + portproxy need Admin rights.
    echo [INFO] Relaunching as Administrator...
    powershell -Command "Start-Process cmd -Verb RunAs -ArgumentList '/c cd /d %CD% && %~f0 %VAULT% %PORT%'" -WindowStyle Hidden
    exit /b 0
)
echo [OK] Running as Administrator

:: ══════════════════════════════════════════════════════════════════════
echo.
echo ========================================
echo   Obsidian CDP Debug
echo   Vault: %VAULT%
echo   Port:  %PORT%
echo ========================================

:: ── Step 1: Kill Obsidian ───────────────────────────────────────────
echo.
echo [1/5] Stopping existing Obsidian...
set KILLED=0
tasklist /fi "imagename eq Obsidian.exe" 2>nul | find /i "Obsidian.exe" >nul
if errorlevel 1 (
    echo [OK] No Obsidian processes found
) else (
    echo [INFO] Obsidian running — killing...
    taskkill /f /im Obsidian.exe >nul 2>&1
    if errorlevel 1 (
        echo [FAIL] Could not kill Obsidian
    ) else (
        echo [OK] Obsidian killed
        set KILLED=1
    )
)

if "%KILLED%"=="1" (
    echo [INFO] Waiting 3s for cleanup...
    timeout /t 3 /nobreak >nul
)

:: ── Step 2: Find Obsidian.exe ──────────────────────────────────────
echo.
echo [2/5] Locating Obsidian.exe...
set OBSIDIAN=
for %%p in (
    "%LOCALAPPDATA%\Obsidian\Obsidian.exe"
    "%LOCALAPPDATA%\obsidian\Obsidian.exe"
    "%APPDATA%\Obsidian\Obsidian.exe"
) do (
    if exist %%p (
        set OBSIDIAN=%%~p
        echo [OK] Found: %%p
        goto :obsidian_found
    )
)
:obsidian_found
if "%OBSIDIAN%"=="" (
    echo [FAIL] Obsidian.exe not found
    echo        Install from https://obsidian.md/download
    pause
    exit /b 1
)

:: ── Step 3: Launch Obsidian with CDP ────────────────────────────────
echo.
echo [3/5] Launching Obsidian with CDP...
echo [INFO] Port: %PORT%
echo [INFO] Vault: %VAULT%

:: Use PowerShell Start-Process (reliable, never parses -- as operator)
powershell -Command "$p = Start-Process -FilePath '%OBSIDIAN%' -ArgumentList '--remote-debugging-port=%PORT%','--remote-debugging-address=0.0.0.0','--remote-allow-origins=*','%VAULT%' -PassThru; Write-Output $p.Id"
if errorlevel 1 (
    echo [FAIL] Could not launch Obsidian
    pause
    exit /b 1
)
echo [OK] Obsidian launched

:: ── Step 4: Wait for CDP ────────────────────────────────────────────
echo.
echo [4/5] Waiting for CDP on 127.0.0.1:%PORT% ...
set CDP_READY=0
for /l %%i in (1,1,30) do (
    <nul set /p =.
    curl -s http://127.0.0.1:%PORT%/json >nul 2>&1
    if not errorlevel 1 (
        set CDP_READY=1
        echo.
        echo [OK] CDP listening on 127.0.0.1:%PORT% ^(took %%is^)
        goto :cdp_ready
    )
    timeout /t 1 /nobreak >nul
)
:cdp_ready

if "%CDP_READY%"=="0" (
    echo.
    echo [FAIL] CDP did not start within 30s
    echo [INFO] Check manually:
    echo        netstat -ano ^| findstr %PORT%
    echo        curl http://127.0.0.1:%PORT%/json
    echo [INFO] Network setup will continue anyway...
) else (
    :: Quick verify — show targets
    for /f "delims=" %%t in ('curl -s http://127.0.0.1:%PORT%/json 2^>nul') do (
        echo [INFO] CDP response received ^(%%t bytes^)
        goto :cdp_verified
    )
    :cdp_verified
)

:: ── Step 5: Network setup ───────────────────────────────────────────
echo.
echo [5/5] Network setup...

:: Detect IP
set LOCAL_IP=UNKNOWN
for /f "tokens=*" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { \$_.IPAddress -notmatch '^127|^169' } | Select-Object -First 1).IPAddress" 2^>nul') do (
    if not "%%a"=="" set LOCAL_IP=%%a
)
if "%LOCAL_IP%"=="UNKNOWN" (
    for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /R "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*" 2^>nul') do (
        if "!LOCAL_IP!"=="UNKNOWN" (
            for /f "tokens=1" %%b in ("%%a") do (
                set IP=%%b
                set IP=!IP: =!
                echo !IP! | findstr /B "127. 169.254." >nul
                if errorlevel 1 set LOCAL_IP=!IP!
            )
        )
    )
)

:: Firewall
netsh advfirewall firewall delete rule name="Obsidian CDP" >nul 2>&1
netsh advfirewall firewall add rule name="Obsidian CDP" dir=in action=allow protocol=TCP localport=%PORT% >nul 2>&1
if errorlevel 1 (
    echo [WARN] Could not add firewall rule
) else (
    echo [OK] Firewall rule added for port %PORT%
)

:: Port proxy
netsh interface portproxy delete v4tov4 listenport=%PORT% listenaddress=0.0.0.0 >nul 2>&1
netsh interface portproxy add v4tov4 listenport=%PORT% listenaddress=0.0.0.0 connectport=%PORT% connectaddress=127.0.0.1 >nul 2>&1
if errorlevel 1 (
    echo [WARN] Could not add port proxy
) else (
    echo [OK] Port proxy: 0.0.0.0:%PORT% -^> 127.0.0.1:%PORT%
)

:: Verify port
netstat -ano | findstr ":%PORT% " >nul 2>&1
if errorlevel 1 (
    echo [WARN] Port %PORT% not in netstat ^(may be normal with portproxy^)
) else (
    echo [OK] Port %PORT% confirmed in netstat
)

:: ══════════════════════════════════════════════════════════════════════
echo.
echo ============================================
echo   Obsidian CDP — READY
echo ============================================
echo   Vault:    %VAULT%
echo   Port:     %PORT%
echo   CDP:      %CDP_READY% (1=online, 0=waiting)
echo   This PC:  %LOCAL_IP%
echo ============================================
echo.
echo Remote dev machine:
echo   CDP_HOST=%LOCAL_IP% python3 debug.py test
echo   CDP_HOST=%LOCAL_IP% python3 debug.py screenshot
echo   CDP_HOST=%LOCAL_IP% python3 debug.py eval "js"
echo.
echo Local test:
echo   python3 debug.py test --local
echo.
echo Press Ctrl+C or close this window to stop Obsidian.
echo ^(firewall + portproxy auto-removed on exit^)
echo.

:: ── Self-test ───────────────────────────────────────────────────────
if "%CDP_READY%"=="1" (
    echo Running quick self-test...
    echo.

    :: Use PowerShell to do a proper CDP query
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$r = Invoke-WebRequest -Uri 'http://127.0.0.1:%PORT%/json' -UseBasicParsing; " ^
        "$t = $r.Content | ConvertFrom-Json; " ^
        "$p = $t | Where-Object { \$_.type -eq 'page' }; " ^
        "Write-Host '  [OK] Found' \$p.Count 'Obsidian page(s)'; " ^
        "foreach (\$pg in \$p) { Write-Host '       Title:' \$pg.title }"

    if errorlevel 1 (
        echo   [WARN] Self-test failed — CDP may still be starting
    )
)

:: ── Wait & cleanup ──────────────────────────────────────────────────
echo.
echo Obsidian is running. Close this window to stop and cleanup.
pause >nul

echo.
echo Cleaning up...
netsh interface portproxy delete v4tov4 listenport=%PORT% listenaddress=0.0.0.0 >nul 2>&1
netsh advfirewall firewall delete rule name="Obsidian CDP" >nul 2>&1
echo [OK] Firewall + portproxy removed.
echo.
choice /c yn /m "Kill Obsidian"
if errorlevel 2 goto :no_kill
taskkill /f /im Obsidian.exe >nul 2>&1
echo [OK] Obsidian stopped.
:no_kill
endlocal
