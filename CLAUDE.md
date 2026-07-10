# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Obsidian Terminal** — a minimal Obsidian plugin that embeds a real bash terminal into the workspace. UX modelled after IntelliJ IDEA's terminal: ribbon icon + Command Palette entry, terminal opens as a bottom pane.

Tech stack: TypeScript, esbuild, xterm.js (`@xterm/xterm` v5), node-pty (`@lydell/node-pty` v1), vanilla DOM (no UI framework).

The Obsidian vault for dev testing is mounted at `/Users/pavel/obsidian-notes`.

### Architecture

```
src/main.ts          — Plugin entry: register view, ribbon icon, command
src/TerminalView.ts  — ItemView subclass, owns xterm.js Terminal + FitAddon + WebglAddon
src/PtyBridge.ts     — node-pty wrapper: spawn $SHELL, pipe data between PTY and xterm
```

Data flow: `xterm.onData → pty.write → shell → pty.onData → xterm.write`

### Build & Dev

```bash
npm run dev      # esbuild watch mode (~30ms rebuilds)
npm run build    # type-check + production bundle
```

Obsidian loads the compiled `main.js` + `styles.css` from the plugin directory. After changes, reload Obsidian (`Ctrl+R`) or use the Hot Reload plugin.

The plugin is **desktop only** (`isDesktopOnly: true`) because node-pty requires Node.js native addon support.

### Key constraints

- Plugin format: CommonJS (`format: "cjs"` in esbuild)
- Obsidian API (`obsidian`) and node builtins must be in esbuild `external`
- Target Obsidian minAppVersion: 1.5.0+
- `Ctrl+C`/`Ctrl+V` pass through to PTY; clipboard uses `Ctrl+Shift+C`/`Ctrl+Shift+V`
- PTY process must be killed in `onClose()` to avoid zombie shells
- node-pty native addon must match Obsidian's Electron ABI — use `@lydell/node-pty` for better prebuild coverage

## Development Environment

This project uses **claudocker** — a Docker-based containerized development environment.

- **Docker Compose config:** `.claudocker/docker-compose.claudocker.yml`
- **Mount settings:** `.claudocker/settings.json`
- The container runs as `dev` user (uid 501, gid 20) inside `/home/dev`
- Permissions are skipped in the container (`CLAUDE_DANGEROUS_SKIP_PERMISSIONS=true`)

### Mounted Directories

- `$PWD` → project directory (read/write inside container)
- `~/.claude` → `/home/dev/.claude` (Claude config/history)
- `~/.claude.json` → `/home/dev/.claude.json` (Claude auth)
- `/Users/pavel/obsidian-notes` → Obsidian vault (external data)
- `~/.claudocker/local` → `/home/dev/.claudocker-persist` (persistent container storage)

### Custom Skills

| Skill | Description |
|---|---|
| `mounts` | Show mounted directories configured for claudocker |
