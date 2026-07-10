# Obsidian Terminal Plugin — Project Estimation

> **Stage:** Pre-implementation analysis
> **Date:** 2026-07-10
> **Goal:** Minimal viable terminal plugin for Obsidian with IntelliJ IDEA-like UX

---

## 1. Summary

Build the simplest possible Obsidian plugin that embeds a real bash terminal into the workspace. The user opens it via a ribbon icon (left sidebar) or Command Palette (`Terminal: Open`), and a terminal pane appears at the bottom of the window with a working bash shell. Core interaction: copy and paste work intuitively.

| Dimension | Estimate (tokens) |
|---|---|
| Documentation & Research | 30,000 – 50,000 |
| Implementation | 25,000 – 45,000 |
| Verification & Debug | 15,000 – 25,000 |
| **Total** | **70,000 – 120,000** |

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│  Obsidian App (Electron)                             │
│  ┌────────────────────────────────────────────────┐  │
│  │  Plugin (main.ts)                              │  │
│  │  ├─ registerView(TerminalView)                 │  │
│  │  ├─ addRibbonIcon("terminal", ...)             │  │
│  │  └─ addCommand("Terminal: Open", ...)          │  │
│  ├────────────────────────────────────────────────┤  │
│  │  TerminalView (extends ItemView)               │  │
│  │  ├─ xterm.js instance                          │  │
│  │  ├─ FitAddon (auto-resize)                     │  │
│  │  └─ WebglAddon (GPU rendering)                 │  │
│  ├────────────────────────────────────────────────┤  │
│  │  PtyBridge                                    │  │
│  │  ├─ node-pty spawn($SHELL)                    │  │
│  │  ├─ stdin  ← xterm.onData()                   │  │
│  │  └─ stdout → xterm.write()                    │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

### 2.1 Technology Stack

| Layer | Technology | Why |
|---|---|---|
| Terminal emulator | `@xterm/xterm` v5.x | Zero deps, mature, standard in Obsidian ecosystem |
| PTY backend | `node-pty` v1.x | Only way to get a real interactive shell (bash, vim, htop) |
| Addons | `@xterm/addon-fit` | Auto-resize terminal to container |
| Addons | `@xterm/addon-webgl` | GPU-accelerated rendering |
| Build | `esbuild` | Obsidian standard, <50ms rebuilds |
| Language | TypeScript (strict) | Obsidian API is typed, catches PTY bugs early |

### 2.2 Source Files (Minimal)

```
obsidian-terminal/
├── src/
│   ├── main.ts              # Plugin entry (~60 lines)
│   ├── TerminalView.ts      # ItemView + xterm.js (~120 lines)
│   └── PtyBridge.ts         # node-pty wrapper (~80 lines)
├── styles.css               # Terminal styling (~30 lines)
├── manifest.json            # Plugin metadata
├── package.json
├── tsconfig.json
├── esbuild.config.mjs       # Build config
└── versions.json            # Min AppVersion compat
```

**Total: ~3 source files, ~260 lines of logic** — deliberately minimal.

### 2.3 View Registration Pattern

```typescript
// main.ts — onload()
this.registerView(VIEW_TYPE_TERMINAL, (leaf) => new TerminalView(leaf));

// Open bottom pane
this.addRibbonIcon("terminal", "Open terminal", () => this.openTerminal());
this.addCommand({
  id: "open-terminal",
  name: "Open terminal",
  callback: () => this.openTerminal(),
});
```

```typescript
// openTerminal() — activate or create leaf at bottom
async openTerminal() {
  const { workspace } = this.app;
  let leaf = workspace.getLeavesOfType(VIEW_TYPE_TERMINAL)[0];
  if (!leaf) {
    leaf = workspace.getLeaf("split", "horizontal");
    await leaf.setViewState({ type: VIEW_TYPE_TERMINAL, active: true });
  }
  workspace.revealLeaf(leaf);
}
```

### 2.4 PTY Data Flow

```
User types in xterm
  → xterm.onData(data)
    → pty.write(data)
      → bash stdin
        → bash stdout
          → pty.onData(data)
            → xterm.write(data)
              → Rendered in terminal
```

Key detail: On `onClose()` of the view, the PTY process must be killed (`pty.kill()`) to avoid zombie shells.

---

## 3. Implementation Plan

### Phase 1: Project Scaffold (5,000 – 8,000 tokens)

- Initialize npm project, install dependencies
- Copy standard esbuild config from obsidian-sample-plugin
- Create `manifest.json`, `tsconfig.json`, `versions.json`
- Set up `styles.css` with basic terminal styling
- Verify empty plugin loads in Obsidian

### Phase 2: Terminal View + xterm.js (10,000 – 18,000 tokens)

- Create `TerminalView.ts` extending `ItemView`
- Instantiate `Terminal` from `@xterm/xterm`
- Load `FitAddon` and `WebglAddon`
- Mount xterm into `contentEl`
- Handle resize events (Obsidian pane resize → fit addon)
- Implement copy/paste handling:
  - Selection → clipboard (xterm.js built-in)
  - `Ctrl+Shift+C` / `Ctrl+Shift+V` for clipboard operations
  - `Ctrl+C` / `Ctrl+V` pass through to PTY for shell operations

### Phase 3: PTY Bridge (10,000 – 20,000 tokens)

- Create `PtyBridge.ts`
- Detect shell: `process.env.SHELL` on macOS/Linux, `powershell.exe` on Windows
- Spawn via `node-pty.spawn(shell, [], { cwd, env, cols, rows })`
- Pipe: `pty.onData()` → `xterm.write()`
- Pipe: `xterm.onData()` → `pty.write()`
- Handle terminal resize: `xterm.onResize()` → `pty.resize(cols, rows)`
- Clean exit: kill PTY on view close, handle shell exit gracefully

### Phase 4: Integration & Polish (5,000 – 10,000 tokens)

- Ribbon icon + Command Palette registration
- `isDesktopOnly: true` in manifest (node-pty requires Node.js)
- Theme sync: match Obsidian color scheme in terminal
- Focus management: auto-focus terminal on open
- Graceful degradation: show error if node-pty fails to load

---

## 4. Key Design Decisions

### 4.1 Why node-pty and not child_process?

`child_process.spawn` creates a pipe, not a PTY. Interactive programs (vim, htop, ssh, any TUI) will not work — they expect a TTY. `node-pty` allocates a pseudo-terminal, making the shell behave exactly as in a real terminal emulator.

### 4.2 Why xterm.js and not a custom renderer?

xterm.js is the de-facto standard for browser terminals. It handles:
- ANSI/VT escape sequences
- Unicode, CJK characters, emoji
- Mouse events
- Selection & clipboard
- Link detection (via addon)

Building even a subset of this from scratch would be 10x the effort.

### 4.3 Single terminal vs multiple tabs

**V1 decision: single terminal.** Multiple terminals add tab management complexity (tab bar UI, multiple PTY instances, tab state). The user asked for minimal — one terminal is the 80/20.

### 4.4 Bottom pane vs sidebar

**V1 decision: bottom pane** (`workspace.getLeaf("split", "horizontal")`). This matches IntelliJ IDEA's terminal placement and is the most natural UX for a terminal. Users can drag it elsewhere if desired (Obsidian handles pane rearrangement natively).

### 4.5 Copy/paste handling

| Keystroke | Behavior |
|---|---|
| `Ctrl+Shift+C` | Copy selected text |
| `Ctrl+Shift+V` | Paste clipboard |
| `Ctrl+C` | Send SIGINT to shell |
| `Ctrl+V` | Send literal `\x16` to shell |
| Right-click | Context menu (Copy/Paste) |
| Mouse select | Auto-copy to clipboard |

xterm.js handles mouse selection natively. We configure it to copy on select and handle the keyboard shortcuts.

---

## 5. Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| **node-pty native compilation fails** | Medium | High — no PTY, no real terminal | Use prebuilds (available for all platforms). Fallback: graceful error message. Test on clean macOS, Linux, Windows. |
| **macOS TCC blocks shell spawn** | Low | Medium — terminal opens but bash doesn't start | Obsidian already has filesystem access; shell spawn from renderer is generally allowed. Test on macOS 14+. |
| **Windows ConPTY issues** | Medium | Medium — garbled output or no colors | Use `node-pty`'s built-in ConPTY support. Test with PowerShell and Git Bash. |
| **Obsidian minAppVersion breakage** | Low | Low | Target 1.5.0+ (stable API). Test with latest Obsidian. |
| **xterm.js memory leak on view close** | Low | Medium — grows over time | Ensure `term.dispose()` and `pty.kill()` are called in `onClose()`. |
| **Electron/node-pty version mismatch** | Medium | High — node-pty built for wrong Electron version | Use `electron-rebuild` or match node-pty ABI to Obsidian's Electron version. Obsidian ships Electron ~28.x (2024). |

### 5.1 Biggest Risk: node-pty + Electron ABI Mismatch

This is the main technical risk. Obsidian uses a specific Electron version. node-pty is a native addon compiled against a specific Node.js/Electron ABI. If they don't match, the plugin fails to load.

**How existing plugins handle this:**
- **O-Terminal** maintains prebuilds and uses `@lydell/node-pty` (a maintained fork)
- **Lean Terminal** has an `arm64-prebuilds/` directory and `patches/` for platform quirks
- Both ship the prebuilt `.node` binary for common platform+arch combinations

**Our V1 approach:** Use `@lydell/node-pty` (better prebuild coverage). If the native addon fails to load, show a clear error message explaining how to rebuild (`npm rebuild node-pty --target=<electron-version>`).

---

## 6. Alternatives Considered

| Alternative | Pros | Cons | Verdict |
|---|---|---|---|
| **xterm.js + node-pty** | Real shell, mature ecosystem, existing plugins use this | Native compilation, platform quirks | ✅ **Chosen** — only viable path for real terminal |
| **xterm.js + child_process** | No native deps, simpler | No PTY = no vim/htop/ssh, signal handling broken | ❌ Not a real terminal |
| **WebContainer (StackBlitz)** | Pure WASM, no native deps | No real bash, no filesystem access, over-engineered | ❌ Wrong abstraction |
| **Open external terminal** (e.g., `child_process.exec('open -a Terminal')`) | Zero terminal emulation code | No integration with Obsidian workspace, poor UX | ❌ Not embedded, defeats the purpose |
| **Obsidian ShellCommands plugin** | Existing, mature | Not embedded — runs commands, not a terminal | ❌ Different use case |
| **iframe to web-based terminal** (ttyd, wetty) | External process, no PTY in plugin | Requires separate server, security concerns, no Obsidian integration | ❌ Over-complicated |
| **Rust PTY backend** (like Termy) | No Node.js native deps, WASM | Different toolchain, harder to iterate, smaller ecosystem | ❌ Over-engineered for V1 |

---

## 7. Dependencies

### Runtime
| Package | Version | Purpose |
|---|---|---|
| `@xterm/xterm` | ^5.5.0 | Terminal emulator |
| `@xterm/addon-fit` | ^0.10.0 | Auto-resize |
| `@xterm/addon-webgl` | ^0.18.0 | GPU rendering |
| `@lydell/node-pty` | ^1.1.0 | PTY backend (maintained fork) |

### Dev
| Package | Version | Purpose |
|---|---|---|
| `obsidian` | latest | Obsidian API types |
| `typescript` | ^5.5 | Type checking |
| `esbuild` | latest | Bundler |
| `@types/node` | ^20 | Node.js types |
| `builtin-modules` | latest | esbuild external list |

### Not Needed (V1)
- React / Svelte / any UI framework (vanilla TypeScript is simpler)
- State management library (terminal state is local to the view)
- Testing framework (V1 — manual testing; add vitest later)

---

## 8. Verification Plan

### 8.1 Manual Test Cases

| # | Test | Expected Result |
|---|---|---|
| 1 | Click ribbon icon | Terminal opens at bottom |
| 2 | `Terminal: Open` from Command Palette | Terminal opens at bottom |
| 3 | Type `ls`, press Enter | Lists files in vault directory |
| 4 | Type `echo $SHELL` | Shows bash path |
| 5 | Run `vim test.txt` | Vim opens, works, `:q` exits |
| 6 | Run `htop` | Interactive process viewer works |
| 7 | `Ctrl+C` on running process | Sends SIGINT, process stops |
| 8 | Select text with mouse | Text copied to clipboard |
| 9 | `Ctrl+Shift+V` | Pastes clipboard content |
| 10 | Resize Obsidian pane | Terminal re-fits to new size |
| 11 | Close terminal view | Shell exits cleanly, no zombie process |
| 12 | Reopen terminal after close | Fresh shell starts |
| 13 | `Ctrl+D` in empty shell | Shell exits, terminal shows "Process exited" |
| 14 | Run `ssh localhost` | Interactive SSH prompt works |

### 8.2 Platform Matrix

| Platform | Test Priority |
|---|---|
| macOS (ARM64) | P1 — primary dev platform |
| macOS (x64) | P2 |
| Linux (x64) | P2 — Docker-based test |
| Windows 11 | P3 — V1 defer if complex |

### 8.3 Verification Tokens (15,000 – 25,000)

- 5,000–8,000: Test execution (14 cases × platform)
- 5,000–8,000: Bug fixes from test findings
- 5,000–9,000: Edge case handling (shell env, paths, permissions)

---

## 9. Token Budget Detail

### Documentation & Research (30k – 50k)

| Activity | Tokens | Notes |
|---|---|---|
| Read Obsidian plugin API docs (Views, Workspace) | 8k – 12k | Already partially done |
| Read xterm.js docs & API reference | 5k – 8k | Terminal, addons, clipboard |
| Read node-pty docs & Electron integration | 5k – 8k | Spawn, resize, kill, ABI |
| Study reference implementations (Lean Terminal, O-Terminal) | 8k – 14k | Source reading, pattern extraction |
| Study obsidian-sample-plugin build setup | 2k – 4k | esbuild config, manifest |
| Platform-specific research (ConPTY, macOS TCC) | 2k – 4k | Only if issues arise |

### Implementation (25k – 45k)

| Phase | Tokens | Files |
|---|---|---|
| Scaffold (config files, manifest, build) | 5k – 8k | 6 files |
| TerminalView + xterm.js | 10k – 18k | `TerminalView.ts`, `styles.css` |
| PtyBridge (node-pty) | 10k – 20k | `PtyBridge.ts` |
| Integration (ribbon, command, polish) | 5k – 10k | `main.ts` updates |

### Verification (15k – 25k)

| Activity | Tokens |
|---|---|
| Test execution & debugging | 10k – 16k |
| Fixes from findings | 5k – 9k |

### Grand Total: **70,000 – 120,000 tokens**

This is a **small project**. For comparison, a single complex code review can be 50k–80k tokens. The entire plugin is ~260 lines of TypeScript.

---

## 10. What This Plugin Is NOT (V1 Scope Boundaries)

- ❌ Multiple terminal tabs
- ❌ Split panes
- ❌ Custom shell configuration UI (uses `$SHELL`)
- ❌ Session persistence
- ❌ AI/Claude Code integration
- ❌ File tree or drag-and-drop
- ❌ Mobile support (`isDesktopOnly: true`)
- ❌ Custom color themes (uses Obsidian theme variables)
- ❌ Plugin settings tab (not needed for V1 — just bash)

---

## 11. Next Steps (After This Estimation)

1. **Initialize git repo** — `git init`, first commit with `CLAUDE.md` and this estimation
2. **Scaffold project** — Create all config files, verify empty plugin loads
3. **Implement TerminalView** — xterm.js rendering in ItemView
4. **Implement PtyBridge** — node-pty shell spawn and data piping
5. **Integration** — Ribbon icon, Command Palette, copy/paste
6. **Verification** — Run test cases on macOS, fix issues
7. **Tag v0.1.0**
