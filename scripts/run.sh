#!/usr/bin/env bash
set -euo pipefail

# For development: copy built plugin to a test vault and open Obsidian
# This script assumes the plugin is already built (npm run build)

VAULT="${1:-}"

if [ -z "$VAULT" ]; then
  echo "Usage: ./scripts/run.sh <vault-path>"
  echo ""
  echo "Copies the built plugin into the vault's .obsidian/plugins/ and opens Obsidian."
  exit 1
fi

PLUGIN_DIR="$VAULT/.obsidian/plugins/minimalist-terminal"

mkdir -p "$PLUGIN_DIR"
cp main.js manifest.json styles.css "$PLUGIN_DIR/"

echo "Plugin installed to $PLUGIN_DIR"
echo "Open Obsidian and enable the plugin: Settings → Community Plugins → Terminal → Enable"
