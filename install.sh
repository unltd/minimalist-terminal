#!/usr/bin/env bash
set -euo pipefail

# Install obsidian-terminal plugin into an Obsidian vault.
# Usage: ./install.sh [vault-path]
#
# vault-path is required — either as a command-line argument or
# entered interactively when prompted.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT="${1:-}"

if [ -z "$VAULT" ]; then
  while [ -z "$VAULT" ]; do
    read -r -p "Enter vault path: " VAULT
  done
fi

# Remove trailing slash
VAULT="${VAULT%/}"

if [ ! -d "$VAULT" ]; then
  echo "Error: vault not found at $VAULT"
  exit 1
fi

TARGET="$VAULT/.obsidian/plugins/obsidian-terminal"
echo "Installing to $TARGET ..."

mkdir -p "$TARGET"
cp "$SCRIPT_DIR/main.js"       "$TARGET/"
cp "$SCRIPT_DIR/manifest.json" "$TARGET/"
cp "$SCRIPT_DIR/styles.css"    "$TARGET/"
cp "$SCRIPT_DIR/package.json"  "$TARGET/"

echo ""
echo "Installing dependencies..."
if command -v npm &>/dev/null; then
  (cd "$TARGET" && npm install --production) || echo "[WARN] npm install failed"
else
  echo "[WARN] npm not found — skipping dependency install."
  echo "       Install Node.js (https://nodejs.org) and run:"
  echo "       cd \"$TARGET\" && npm install --production"
fi

echo ""
echo "Done! Now enable the plugin:"
echo "  Settings > Community Plugins > Terminal > Enable"
echo ""
echo "For CDP testing (macOS):"
echo "  open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=* \"$VAULT\""
