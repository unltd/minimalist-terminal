# Obsidian Terminal

Embedded terminal for [Obsidian](https://obsidian.md) — run CLI tools, use AI agents right inside your vault.

[![Version](https://img.shields.io/github/v/release/unltd/obsidian-terminal)](https://github.com/unltd/obsidian-terminal/releases)
[![License](https://img.shields.io/github/license/unltd/obsidian-terminal)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/unltd/obsidian-terminal/ci.yml)](https://github.com/unltd/obsidian-terminal/actions)

![Terminal screenshot](assets/terminal-screenshot.png)

## Features

- **Configurable shell** — zsh (default), bash, fish, or custom path via Settings Tab
- **Auto-detection** — finds available shells on your system, prefers modern ones
- **Multi-terminal** — independent terminal tabs, no artificial limit
- **Clipboard** — `Ctrl+V` paste, `Ctrl+C` copy (with selection), `Ctrl+Shift+C` copy, right-click paste
- **Resize-aware** — terminal fits the pane, columns/rows synced to PTY
- **Auto-focus** — terminal grabs focus on open
- **Dark theme** — matches Obsidian's default look

## Quickstart

### Installation

Install via **Obsidian Community Plugins**:

1. Settings → Community Plugins → Browse
2. Search for **Terminal**
3. Install and Enable

### Open a terminal

- Click the **terminal icon** in the ribbon (left sidebar)
- Or use the Command Palette: `Cmd+P` → "Open terminal"

### Configure your shell (optional)

Settings → Community Plugins → **Terminal** → Options (⚙️) → choose from detected shells or enter a custom path.

### Development setup

```bash
# Clone into your vault's plugins directory
cd <vault>/.obsidian/plugins/
git clone https://github.com/unltd/obsidian-terminal.git
cd obsidian-terminal
npm install
npm run build
```

Or use the included install script:

```bash
./install.sh [vault-path]
```

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS (x64) | ✅ Tested | Primary development platform; `@lydell/node-pty-darwin-x64` |
| macOS (arm64) | ✅ Tested | `@lydell/node-pty-darwin-arm64` |
| Linux | ⚠️ Untested | Build passes but runtime not tested — community reports welcome |
| Windows | ✅ Tested (basic) | ConPTY via `@lydell/node-pty` — shell detection, PowerShell/CMD/WSL; advanced ConPTY edge cases tracked separately |
| Mobile (iOS/Android) | ❌ Unsupported | Requires Node.js native addon |

The plugin is **desktop only** (`isDesktopOnly: true`). It uses [node-pty](https://github.com/lydell/node-pty) for pseudo-terminal support, which requires a native Node.js addon matching Obsidian's Electron ABI.

## Limitations

- **Limited settings** — shell selection exists, but font size, theme, and scrollback are still hardcoded
- **No theme sync** — terminal colors don't follow Obsidian's theme changes
- **No hotkey customization** — clipboard shortcuts are hardcoded
- **No session persistence** — terminals are lost on Obsidian restart (tmux/screen integration planned)
- **No tab completion** — Tab key is intercepted by Obsidian; autocomplete not yet implemented
- **No sidebar mode** — terminal only opens as a bottom pane for now
- **Windows ConPTY — basic support** — shell detection, PowerShell/CMD/WSL work. Advanced ConPTY edge cases (escape sequences, performance, resize behavior) are tracked but not yet covered

## Known Issues

### Focus wrestling

Obsidian may steal focus from the terminal after opening or when switching tabs. The plugin fights back with a retry loop, but occasional manual clicks may be needed.

## Architecture

```mermaid
graph TD
    A[User] -->|types| B[xterm.js]
    B -->|onData| C[PtyBridge]
    C -->|write| D[node-pty]
    D -->|spawn| E[zsh / bash / fish]
    E -->|stdout| D
    D -->|onData| C
    C -->|write| B
    B -->|DOM| A
```

**Files:**

| File | Role |
|------|------|
| `src/main.ts` | Plugin entry: register view, ribbon, commands, settings |
| `src/TerminalView.ts` | `ItemView` subclass: xterm.js Terminal + FitAddon |
| `src/PtyBridge.ts` | node-pty wrapper: spawn configured shell, pipe data |
| `src/settings.ts` | Shell detection, resolution, shell-specific flags |
| `src/SettingsTab.ts` | Settings UI: dropdown + custom path with validation |
| `styles.css` | Terminal styling + xterm.js CSS protection rules |

**Tech stack:** TypeScript, esbuild, xterm.js v5, node-pty v1, vanilla DOM.

**Key constraint:** Obsidian applies global CSS to all DOM elements, which breaks xterm.js's internal coordinate grid. The plugin protects critical xterm.js elements with `position`, `overflow`, and `user-select` overrides.

## Development

```bash
npm run dev      # Watch mode (~30ms rebuilds)
npm run build    # Type-check + production bundle
```

See [`CLAUDE.md`](CLAUDE.md) for detailed development notes, CDP testing workflow, and container setup.

### Testing

Tests use Gauge BDD framework + pytest for CDP-based browser automation:

```bash
# Run all specs
gauge run tests/specs/

# CDP debug mode — connect to a running Obsidian for step-by-step debugging
./dev-kit/debug/debug.sh    # macOS
dev-kit\debug\debug.bat      # Windows
```

See `dev-kit/README.md` and `dev-kit/cdp-testing.md` for CDP setup details.

## Roadmap

- [x] Settings tab: shell selection
- [x] Windows support (basic ConPTY)
- [ ] Settings tab: font size, theme, scrollback
- [ ] Canvas/WebGL renderer support (performance)
- [ ] Sidebar mode (left/right panel)
- [ ] Session persistence via tmux/screen
- [ ] Advanced Windows support (ConPTY edge cases)
- [ ] Tab completion (navigate Obsidian hotkey conflicts)
- [ ] Tab title: current directory or running command

## License

MIT — see [LICENSE](LICENSE) file.
