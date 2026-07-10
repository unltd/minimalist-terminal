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

# Check / install the native binary for the current platform
PTY_PKG_DIR="$(pwd)/node_modules/@lydell/${PTY_PKG##*/}"
if [ -d "$PTY_PKG_DIR" ] && [ -n "$(find "$PTY_PKG_DIR" -name '*.node' -type f 2>/dev/null | head -1)" ]; then
  echo "==> node-pty native binary: OK"
else
  echo ""
  echo "  ==> Installing node-pty native binary: ${PTY_PKG}..."

  if npm install "${PTY_PKG}" 2>&1; then
    echo "  ==> Installed OK."
  else
    echo ""
    echo "  ⚠️  Failed to install ${PTY_PKG}"
    echo "  This is normal if you're in a Docker container."
    echo "  Run install.sh on your REAL machine (macOS) instead:"
    echo ""
    echo "    cd $(pwd) && ./install.sh"
    echo ""
  fi
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
