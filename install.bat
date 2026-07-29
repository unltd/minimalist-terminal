@echo off
setlocal enabledelayedexpansion

:: install.bat — Install obsidian-terminal plugin into an Obsidian vault.
:: Usage: install.bat [vault-path]
::
:: vault-path is required — either as a command-line argument or
:: entered interactively when prompted.

set "PLUGIN_DIR=%~dp0"
set "VAULT=%~1"

:ask_again
if "%VAULT%"=="" (
    set /p "VAULT=Enter vault path: "
    if "!VAULT!"=="" goto :ask_again
)

:: Remove trailing backslash if present
if "!VAULT:~-1!"=="\" set "VAULT=!VAULT:~0,-1!"

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
if !errorlevel! neq 0 goto :no_npm

cd /d "!TARGET!"
call npm install --production
if !errorlevel! neq 0 (
    echo [WARN] npm install failed. Try manually:
    goto :show_manual
)
goto :install_done

:no_npm
echo [WARN] npm not found — skipping dependency install.

:show_manual
echo        cd /d "!TARGET!"
echo        npm install --production

:install_done
echo.
echo Done. Now enable the plugin:
echo   Settings ^> Community Plugins ^> Terminal ^> Enable
echo.
echo For CDP debugging:
echo   debug.bat "!VAULT!"
echo.

pause
endlocal
