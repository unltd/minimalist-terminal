@echo off
setlocal enabledelayedexpansion
title Obsidian CDP Debug

:: ===========================================================================
:: debug.bat v9 — Local + remote modes, CDP connection limit warning
::
:: Usage:  debug.bat <vault-path> [port] [/local] [/nowait]
::   /local  — skip admin, firewall, portproxy (localhost-only)
::   /nowait — don't pause at end
:: ===========================================================================

set VAULT=
set PORT=9222
set MODE=remote
set NOWAIT=0

:: ── Parse args ────────────────────────────────────────────────────────
for %%a in (%*) do (
    if /i "%%a"=="/local"   set MODE=local
    if /i "%%a"=="--local"  set MODE=local
    if /i "%%a"=="/nowait"  set NOWAIT=1
    if /i "%%a"=="--nowait" set NOWAIT=1
)
:: Vault = first non-flag arg, Port = second non-flag arg
for %%a in (%*) do (
    if not defined VAULT (
        if /i not "%%a"=="/local" if /i not "%%a"=="--local" if /i not "%%a"=="/nowait" if /i not "%%a"=="--nowait" (
            set "VAULT=%%a"
        )
    ) else (
        if /i not "%%a"=="/local" if /i not "%%a"=="--local" if /i not "%%a"=="/nowait" if /i not "%%a"=="--nowait" (
            set "PORT=%%a"
        )
    )
)

:: ── Defaults ────────────────────────────────────────────────────────
set CDP_READY=0
set LOCAL_IP=UNKNOWN
set PORT_PROXY_INFO=skipped

if "%VAULT%"=="" (
    echo Usage: debug.bat ^<vault-path^> [port]
    echo   debug.bat C:\Users\tania\Documents\obsidian-test
    exit /b 1
)

if not exist "%VAULT%" mkdir "%VAULT%" 2>nul
if not exist "%VAULT%" (
    echo [FAIL] Vault not found and cannot create: %VAULT%
    pause
    exit /b 1
)

:: ── Admin ───────────────────────────────────────────────────────────
if "%MODE%"=="local" (
    echo [OK] Local mode — skipping admin elevation
) else (
    net session >nul 2>&1
    if errorlevel 1 (
        echo [INFO] Relaunching as Administrator...
        powershell -Command "Start-Process cmd -Verb RunAs -ArgumentList '/c cd /d %CD% && %~f0 %VAULT% %PORT%'" -WindowStyle Hidden
        exit /b 0
    )
    echo [OK] Admin
)

:: ══════════════════════════════════════════════════════════════════════
echo.
echo ========================================
echo   Obsidian CDP Debug v8
echo   Vault: %VAULT%
echo   Port:  %PORT%
echo ========================================

:: ── Step 1: Kill Obsidian + singleton lock ──────────────────────────
echo.
echo [1/6] Stopping Obsidian...
set KILLED=0
tasklist /fi "imagename eq Obsidian.exe" 2>nul | find /i "Obsidian.exe" >nul
if errorlevel 1 (
    echo [OK] Not running
) else (
    echo [INFO] Killing...
    taskkill /f /im Obsidian.exe >nul 2>&1
    set KILLED=1
    echo [OK] Killed
)

:: Clear Electron singleton lock
if exist "%APPDATA%\Obsidian\SingletonLock" del "%APPDATA%\Obsidian\SingletonLock" 2>nul
if exist "%APPDATA%\obsidian\SingletonLock" del "%APPDATA%\obsidian\SingletonLock" 2>nul
echo [OK] SingletonLock cleared

if "%KILLED%"=="1" timeout /t 3 /nobreak >nul

:: ── Step 2: Find Obsidian ───────────────────────────────────────────
echo.
echo [2/6] Finding Obsidian.exe...
set OBSIDIAN=
if exist "%LOCALAPPDATA%\Obsidian\Obsidian.exe" set "OBSIDIAN=%LOCALAPPDATA%\Obsidian\Obsidian.exe"
if exist "%LOCALAPPDATA%\obsidian\Obsidian.exe" set "OBSIDIAN=%LOCALAPPDATA%\obsidian\Obsidian.exe"
if "%OBSIDIAN%"=="" if exist "%APPDATA%\Obsidian\Obsidian.exe" set "OBSIDIAN=%APPDATA%\Obsidian\Obsidian.exe"
if "%OBSIDIAN%"=="" (
    echo [FAIL] Obsidian.exe not found
    pause
    exit /b 1
)
echo [OK] %OBSIDIAN%

:: ── Step 3: Launch ──────────────────────────────────────────────────
echo.
echo [3/6] Launching with CDP (%MODE% mode)...
if "%MODE%"=="local" (
    start "" "%OBSIDIAN%" --remote-debugging-port=%PORT% "%VAULT%"
) else (
    start "" "%OBSIDIAN%" --remote-debugging-port=%PORT% --remote-debugging-address=0.0.0.0 --remote-allow-origins=* "%VAULT%"
)
echo [OK] Launched

:: Verify it's running
set OBSIDIAN_RUNNING=no
for /l %%i in (1,1,5) do (
    timeout /t 1 /nobreak >nul
    tasklist /fi "imagename eq Obsidian.exe" 2>nul | find /i "Obsidian.exe" >nul
    if not errorlevel 1 (
        set OBSIDIAN_RUNNING=yes
        goto :obsidian_ok
    )
)
:obsidian_ok
if "%OBSIDIAN_RUNNING%"=="yes" (echo [OK] Obsidian.exe running) else (echo [WARN] Obsidian.exe not in tasklist)

:: ── Step 4: Wait for CDP ────────────────────────────────────────────
echo.
echo [4/6] Waiting for CDP on 127.0.0.1:%PORT% ...
set CDP_ATTEMPT=0

:cdp_poll
set /a CDP_ATTEMPT+=1
<nul set /p =.
curl -s http://127.0.0.1:%PORT%/json 2>nul >nul
if not errorlevel 1 goto :cdp_ok
if %CDP_ATTEMPT% GEQ 20 goto :cdp_fail
timeout /t 2 /nobreak >nul
goto :cdp_poll

:cdp_ok
set CDP_READY=1
echo.
echo [OK] CDP responding on 127.0.0.1:%PORT% (took ~%CDP_ATTEMPT%x2s)

:: Quick CDP test — show targets
for /f "tokens=*" %%t in ('curl -s http://127.0.0.1:%PORT%/json 2^>nul') do (
    echo [INFO] CDP response: %%t
    goto :cdp_done
)
goto :cdp_done

:cdp_fail
echo.
echo [FAIL] CDP not responding after 40s
echo [INFO] Check: curl http://127.0.0.1:%PORT%/json
echo [INFO] Check: netstat -ano ^| findstr %PORT%

:cdp_done

:: ── Step 5: Network ─────────────────────────────────────────────────
echo.
if "%MODE%"=="local" (
    echo [5/6] Network setup... skipped ^(local mode^)
    goto :skip_network
)
echo [5/6] Network setup...

:: Detect IP — pure ipconfig, no PowerShell
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /R "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*" 2^>nul') do (
    if "!LOCAL_IP!"=="UNKNOWN" call :try_ip "%%a"
)
echo [INFO] Local IP: %LOCAL_IP%

:: Check CDP bind
set CDP_BIND=unknown
if "%CDP_READY%"=="1" (
    set CDP_BIND=127.0.0.1:%PORT% (localhost)
    netstat -ano | findstr ":%PORT% " | findstr "0.0.0.0:%PORT%" >nul 2>&1
    if not errorlevel 1 set "CDP_BIND=0.0.0.0:%PORT% (all interfaces)"
    echo [INFO] CDP bind: !CDP_BIND!
)

:: Port proxy — only if CDP on localhost
if "%CDP_READY%"=="1" (
    netstat -ano | findstr ":%PORT% " | findstr "0.0.0.0:%PORT%" >nul 2>&1
    if errorlevel 1 (
        echo [INFO] Adding port proxy...
        netsh interface portproxy delete v4tov4 listenport=%PORT% listenaddress=0.0.0.0 >nul 2>&1
        netsh interface portproxy add v4tov4 listenport=%PORT% listenaddress=0.0.0.0 connectport=%PORT% connectaddress=127.0.0.1 >nul 2>&1
        if errorlevel 1 (
            echo [WARN] Port proxy FAILED
            set PORT_PROXY_INFO=FAILED
        ) else (
            echo [OK] Port proxy: 0.0.0.0:%PORT% -^> 127.0.0.1:%PORT%
            set PORT_PROXY_INFO=active
        )
    ) else (
        echo [OK] CDP on 0.0.0.0 — no proxy needed
        set PORT_PROXY_INFO=not needed
    )
)

:: Firewall
netsh advfirewall firewall delete rule name="Obsidian CDP" >nul 2>&1
netsh advfirewall firewall add rule name="Obsidian CDP" dir=in action=allow protocol=TCP localport=%PORT% >nul 2>&1
if errorlevel 1 (
    echo [WARN] Firewall rule may have failed
) else (
    echo [OK] Firewall: port %PORT% allowed
)

:skip_network
:: ══════════════════════════════════════════════════════════════════════
echo.
echo ========================================
echo   SUMMARY
echo ========================================
echo   Vault:      %VAULT%
echo   Port:       %PORT%
echo   Mode:       %MODE%
echo   Obsidian:   %OBSIDIAN_RUNNING%
echo   CDP ready:  %CDP_READY%
echo   CDP bind:   %CDP_BIND%
echo   Local IP:   %LOCAL_IP%
echo   PortProxy:  %PORT_PROXY_INFO%
echo ========================================

if "%CDP_READY%"=="1" (
    echo.
    echo Remote dev machine:
    echo   CDP_HOST=%LOCAL_IP% python3 dev-kit/debug/debug.py test
    echo   CDP_HOST=%LOCAL_IP% python3 dev-kit/debug/debug.py screenshot
    echo.
    echo Local:
    echo   python3 dev-kit/debug/debug.py test --local
)
if "%CDP_READY%"=="0" (
    echo.
    echo [!!] CDP FAILED
    echo   1. Kill all Obsidian from Task Manager
    echo   2. Delete %%APPDATA%%\Obsidian\SingletonLock
    echo   3. Run manually: "%OBSIDIAN%" --remote-debugging-port=%PORT% --remote-debugging-address=0.0.0.0 "%VAULT%"
    echo   4. Check: curl http://127.0.0.1:%PORT%/json
)

echo.
echo   [!] CDP connection limit: after 5-10 debug.py eval calls,
echo       WebSocket connections accumulate and new ones stop responding.
echo       If CDP hangs: close this window, restart Obsidian.
echo.
echo Close this window to cleanup and stop.
if "%NOWAIT%"=="1" goto :cleanup
pause >nul

:: ── Cleanup ─────────────────────────────────────────────────────────
:cleanup
echo.
echo Cleaning up...
netsh interface portproxy delete v4tov4 listenport=%PORT% listenaddress=0.0.0.0 >nul 2>&1
netsh advfirewall firewall delete rule name="Obsidian CDP" >nul 2>&1
echo [OK] PortProxy + Firewall removed.
if "%NOWAIT%"=="1" goto :eof
choice /c yn /m "Kill Obsidian?"
if errorlevel 2 goto :eof
taskkill /f /im Obsidian.exe >nul 2>&1
echo [OK] Stopped.
goto :eof

:: ── Subroutine: try_ip ──────────────────────────────────────────────
:try_ip
set IP=%~1
set IP=%IP: =%
echo %IP% | findstr /B "127. 169.254." >nul
if errorlevel 1 set LOCAL_IP=%IP%
goto :eof
