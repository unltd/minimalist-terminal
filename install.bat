@echo off
setlocal enabledelayedexpansion

:: Install obsidian-terminal plugin into an Obsidian vault.
:: Usage: install.bat [vault-path]
::
:: vault-path is required — either as a command-line argument or
:: entered interactively when prompted.

set "PLUGIN_DIR=%~dp0"
set "VAULT=%~1"

if not "%VAULT%"=="" goto :have_vault

:ask_again
set /p "VAULT=Enter vault path: "
if "%VAULT%"=="" goto :ask_again

:have_vault
:: Remove trailing backslash if present
if "%VAULT:~-1%"=="\" set "VAULT=%VAULT:~0,-1%"

set "TARGET=!VAULT!\.obsidian\plugins\obsidian-terminal"

if not exist "!VAULT!" (
    echo Error: vault not found at !VAULT!
    pause
    exit /b 1
)

echo Installing to !TARGET! ...

if not exist "!TARGET!" mkdir "!TARGET!"

copy /y "%PLUGIN_DIR%\main.js"       "!TARGET!\" >nul
copy /y "%PLUGIN_DIR%\manifest.json" "!TARGET!\" >nul
copy /y "%PLUGIN_DIR%\styles.css"    "!TARGET!\" >nul
copy /y "%PLUGIN_DIR%\package.json"  "!TARGET!\" >nul

echo.
echo Installing dependencies (this may take a minute)...

where npm >nul 2>&1
if !errorlevel!==1 (
    echo [WARN] npm not found — skipping dependency install.
    echo        Install Node.js (https://nodejs.org) and run:
    echo        cd /d "!TARGET!" ^&^& npm install --production
    goto :done
)

cd /d "!TARGET!"
call npm install --production
if !errorlevel!==1 (
    echo [WARN] npm install failed. Try manually:
    echo        cd /d "!TARGET!" ^&^& npm install --production
)

:done
echo.
echo Done! Now enable the plugin:
echo   Settings ^> Community Plugins ^> Terminal ^> Enable
echo.
echo For CDP testing, run: run-cdp.bat "!VAULT!"

pause
endlocal
