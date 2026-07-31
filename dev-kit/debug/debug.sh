#!/usr/bin/env bash
set -euo pipefail

# ===========================================================================
# debug.sh — Launch Obsidian with CDP on macOS
#
# Usage:  ./debug.sh <vault-path> [port] [/local] [/nowait]
#   /local  — localhost only (default on macOS: no --remote-debugging-address)
#   /nowait — don't pause at end
#
# macOS uses `open -a Obsidian --args ...` — no admin, no firewall, no portproxy.
# ===========================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT=""
PORT="9222"
MODE="remote"   # remote = bind 0.0.0.0 (container access), local = 127.0.0.1 only
NOWAIT=0

# ── Parse args ────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        /local|--local)  MODE="local" ;;
        /nowait|--nowait) NOWAIT=1 ;;
        *)
            if [ -z "$VAULT" ]; then
                VAULT="$arg"
            else
                PORT="$arg"
            fi
            ;;
    esac
done

# ── Validation ────────────────────────────────────────────────────────
if [ -z "$VAULT" ]; then
    echo "Usage: debug.sh <vault-path> [port] [/local] [/nowait]"
    echo "  debug.sh ~/obsidian-test"
    echo "  debug.sh ~/obsidian-test 9222"
    echo "  debug.sh ~/obsidian-test /local"
    exit 1
fi

if [ ! -d "$VAULT" ]; then
    mkdir -p "$VAULT" 2>/dev/null || true
    if [ ! -d "$VAULT" ]; then
        echo "[FAIL] Vault not found and cannot create: $VAULT"
        exit 1
    fi
fi

# ══════════════════════════════════════════════════════════════════════
echo
echo "========================================"
echo "  Obsidian CDP Debug (macOS)"
echo "  Vault: $VAULT"
echo "  Port:  $PORT"
echo "  Mode:  $MODE"
echo "========================================"

# ── Step 1: Kill Obsidian + clear singleton lock ──────────────────────
echo
echo "[1/5] Stopping Obsidian..."

OBSIDIAN_PIDS=$(pgrep -f "Obsidian.app/Contents/MacOS/Obsidian" 2>/dev/null || true)
if [ -z "$OBSIDIAN_PIDS" ]; then
    echo "[OK] Not running"
else
    echo "[INFO] Killing Obsidian (PIDs: $OBSIDIAN_PIDS)..."
    kill -9 $OBSIDIAN_PIDS 2>/dev/null || true
    sleep 2
    echo "[OK] Killed"
fi

# Clear Electron singleton locks (macOS paths)
SINGLETON_PATHS=(
    "$HOME/Library/Application Support/Obsidian/SingletonLock"
    "$HOME/Library/Application Support/obsidian/SingletonLock"
    "$HOME/Library/Application Support/Obsidian/SingletonCookie"
    "$HOME/Library/Application Support/obsidian/SingletonCookie"
)
for lock in "${SINGLETON_PATHS[@]}"; do
    if [ -f "$lock" ]; then
        rm -f "$lock"
        echo "[OK] Removed $lock"
    fi
done

# ── Step 2: Launch ────────────────────────────────────────────────────
echo
echo "[2/5] Launching Obsidian with CDP..."

OBSIDIAN_APP="/Applications/Obsidian.app"
OBSIDIAN_BIN="$OBSIDIAN_APP/Contents/MacOS/Obsidian"

if [ ! -f "$OBSIDIAN_BIN" ]; then
    echo "[FAIL] Obsidian binary not found: $OBSIDIAN_BIN"
    echo "[INFO] Install from https://obsidian.md/download"
    exit 1
fi

CDP_URL="http://127.0.0.1:$PORT"

if [ "$MODE" == "local" ]; then
    nohup "$OBSIDIAN_BIN" --remote-debugging-port="$PORT" "$VAULT" > /dev/null 2>&1 &
else
    nohup "$OBSIDIAN_BIN" --remote-debugging-port="$PORT" --remote-debugging-address=0.0.0.0 --remote-allow-origins=* "$VAULT" > /dev/null 2>&1 &
fi
OBSIDIAN_PID=$!
echo "[OK] Launched (PID: $OBSIDIAN_PID)"

# ── Step 3: Wait for CDP ──────────────────────────────────────────────
echo
echo "[3/5] Waiting for CDP on $CDP_URL ..."

ATTEMPT=0
MAX_ATTEMPTS=20
CDP_READY=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    if curl -s "$CDP_URL/json" >/dev/null 2>&1; then
        CDP_READY=1
        break
    fi
    printf "."
    sleep 2
done
echo

if [ "$CDP_READY" -eq 1 ]; then
    echo "[OK] CDP responding on $CDP_URL (took ~$((ATTEMPT * 2))s)"
    echo "[INFO] CDP targets:"
    curl -s "$CDP_URL/json" 2>/dev/null | python3 -c "
import json, sys
try:
    targets = json.load(sys.stdin)
    for t in targets:
        print(f\"  {t.get('id','?')[:30]}... {t.get('title','?')[:50]}  {t.get('url','?')[:60]}\")
except: pass
" 2>/dev/null || true
else
    echo "[FAIL] CDP not responding after $((MAX_ATTEMPTS * 2))s"
    echo "[INFO] Check: curl $CDP_URL/json"
    echo "[INFO] Check: lsof -i :$PORT"
fi

# ── Step 4: Network info ──────────────────────────────────────────────
echo
echo "[4/5] Network..."

if [ "$MODE" == "local" ]; then
    echo "[INFO] Local mode — CDP on 127.0.0.1:$PORT only"
    echo "[INFO] Container access: NOT available (use remote mode)"
else
    # Show local IP for container access
    LOCAL_IP=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    if [ -z "$LOCAL_IP" ]; then
        LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "unknown")
    fi
    echo "[INFO] Local IP: $LOCAL_IP"
    echo "[INFO] CDP bind: 0.0.0.0:$PORT (all interfaces)"

    # Check if CDP is actually accessible via the interface
    if [ "$CDP_READY" -eq 1 ] && [ -n "$LOCAL_IP" ] && [ "$LOCAL_IP" != "unknown" ]; then
        if curl -s "http://$LOCAL_IP:$PORT/json" >/dev/null 2>&1; then
            echo "[OK] CDP accessible at http://$LOCAL_IP:$PORT"
        else
            echo "[WARN] CDP NOT accessible at http://$LOCAL_IP:$PORT (check firewall)"
        fi
    fi
fi

# ── Step 5: Summary ───────────────────────────────────────────────────
echo
echo "========================================"
echo "  SUMMARY"
echo "========================================"
echo "  Vault:      $VAULT"
echo "  Port:       $PORT"
echo "  Mode:       $MODE"
echo "  CDP ready:  $CDP_READY"
echo "  CDP URL:    $CDP_URL"
echo "========================================"

if [ "$CDP_READY" -eq 1 ]; then
    echo
    echo "Container (from project root):"
    echo "  python3 dev-kit/cdp/cdp-eval.py 'app.plugins.enablePlugin(\"obsidian-terminal\")'"
    echo "  python3 dev-kit/cdp/cdp-screenshot.py"
    echo
    echo "Host:"
    echo "  curl $CDP_URL/json"
fi

if [ "$CDP_READY" -eq 0 ]; then
    echo
    echo "[!!] CDP FAILED"
    echo "  1. Kill Obsidian from Activity Monitor"
    echo "  2. Delete: ~/Library/Application Support/Obsidian/SingletonLock"
    echo "  3. Run manually: open -a Obsidian --args --remote-debugging-port=$PORT \"$VAULT\""
    echo "  4. Check: curl $CDP_URL/json"
fi

echo
echo "  Press Ctrl+C to kill Obsidian and exit."

# ── Wait / Cleanup ────────────────────────────────────────────────────
if [ "$NOWAIT" -eq 1 ]; then
    exit 0
fi

# Trap Ctrl+C for cleanup
cleanup() {
    echo
    echo "Cleaning up..."
    OBSIDIAN_PIDS=$(pgrep -f "Obsidian.app/Contents/MacOS/Obsidian" 2>/dev/null || true)
    if [ -n "$OBSIDIAN_PIDS" ]; then
        echo -n "Kill Obsidian? [y/N] "
        read -r answer
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            kill -9 $OBSIDIAN_PIDS 2>/dev/null || true
            echo "[OK] Stopped"
        fi
    fi
    exit 0
}
trap cleanup INT TERM

# Wait for user to close
echo "Press Enter to keep Obsidian running and exit..."
read -r
echo "Obsidian left running on port $PORT."
