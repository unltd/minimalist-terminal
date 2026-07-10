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

# --- node-pty native module setup ---
PTY_DIR="$PLUGIN_DIR/node_modules/@lydell"
mkdir -p "$PTY_DIR"

# Detect Obsidian's actual runtime platform (not the build container)
OBSIDIAN_PLATFORM="${OBSIDIAN_PLATFORM:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
OBSIDIAN_ARCH="${OBSIDIAN_ARCH:-$(uname -m)}"
# Normalize arch: x86_64 → x64, aarch64/arm64 → arm64
case "$OBSIDIAN_ARCH" in
  x86_64|amd64) OBSIDIAN_ARCH="x64" ;;
  aarch64)      OBSIDIAN_ARCH="arm64" ;;
esac

PTY_PKG="@lydell/node-pty-${OBSIDIAN_PLATFORM}-${OBSIDIAN_ARCH}"

echo "==> Obsidian platform: ${OBSIDIAN_PLATFORM}-${OBSIDIAN_ARCH}"
echo "==> node-pty package:  ${PTY_PKG}"

# Symlink the JS wrapper
if [ -d "$(pwd)/node_modules/@lydell/node-pty" ]; then
  ln -sfn "$(pwd)/node_modules/@lydell/node-pty" "$PTY_DIR/node-pty"
fi

# Check / install the native binary for Obsidian's platform
if [ -d "$(pwd)/node_modules/@lydell/${PTY_PKG##*/}" ]; then
  PTY_BIN=$(find "$(pwd)/node_modules/@lydell/${PTY_PKG##*/}" -name '*.node' -type f 2>/dev/null | head -1)
  if [ -n "$PTY_BIN" ]; then
    echo "==> node-pty native binary: OK (${PTY_BIN})"
  fi
else
  echo ""
  echo "  ⚠️  Native binary NOT FOUND for ${OBSIDIAN_PLATFORM}-${OBSIDIAN_ARCH}"
  echo "  The terminal will show an error until this is installed."
  echo ""
  if [ "${OBSIDIAN_PLATFORM}" != "$(uname -s | tr '[:upper:]' '[:lower:]')" ]; then
    echo "  You are building in a container (platform=$(uname -s)/$(uname -m))"
    echo "  but Obsidian runs on ${OBSIDIAN_PLATFORM}/${OBSIDIAN_ARCH}."
    echo "  Run this command on your REAL machine (macOS):"
  else
    echo "  Run:"
  fi
  echo ""
  echo "    cd $(pwd) && npm install ${PTY_PKG}"
  echo ""
fi

# Symlink all @lydell packages (JS wrapper + native binary if present)
for pkg in "$(pwd)"/node_modules/@lydell/*; do
  [ -d "$pkg" ] || continue
  ln -sfn "$pkg" "$PTY_DIR/$(basename "$pkg")"
done

# Hot reload marker
touch "$PLUGIN_DIR/.hotreload" 2>/dev/null || true

echo ""
echo "==> Done. Enable: Settings → Community Plugins → ${PLUGIN_ID}"
echo "==> Tip: Reload Obsidian (Cmd+R) to see changes"
