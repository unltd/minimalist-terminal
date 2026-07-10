#!/usr/bin/env bash
set -euo pipefail

# Install the plugin into an Obsidian vault via symlinks.
# Usage: ./install.sh [vault-path]
# Default vault: /Users/pavel/obsidian-notes

VAULT="${1:-/Users/pavel/obsidian-notes}"
PLUGIN_ID=$(node -e "console.log(require('./manifest.json').id)" 2>/dev/null) || {
  echo "ERROR: manifest.json not found. Run from the project root." >&2
  exit 1
}

PLUGIN_DIR="$VAULT/.obsidian/plugins/$PLUGIN_ID"

echo "==> Vault:  $VAULT"
echo "==> Plugin: $PLUGIN_ID"
echo "==> Target: $PLUGIN_DIR"

# Ensure plugin directory exists
mkdir -p "$PLUGIN_DIR"

# Check required build artifacts
MISSING=()
for f in main.js manifest.json styles.css; do
  [ -f "$f" ] || MISSING+=("$f")
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "==> Building first (missing: ${MISSING[*]})..."
  npm run build
fi

# Symlink build outputs into the vault plugin directory
for f in main.js main.js.map styles.css manifest.json; do
  [ -f "$f" ] || continue
  ln -sfn "$(pwd)/$f" "$PLUGIN_DIR/$f"
done

# Hot reload marker (optional: install the Hot Reload plugin to use this)
touch "$PLUGIN_DIR/.hotreload" 2>/dev/null || true

echo "==> Done. Enable the plugin in Obsidian: Settings → Community Plugins → $PLUGIN_ID"
echo "==> Tip: $ Obsidian → Ctrl+R to reload after code changes"
