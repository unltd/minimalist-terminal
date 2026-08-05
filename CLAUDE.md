# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Minimalist Terminal** — a minimal Obsidian plugin that embeds a real bash terminal into the workspace. UX modelled after IntelliJ IDEA's terminal: ribbon icon + Command Palette entry, terminal opens as a bottom pane.

Tech stack: TypeScript, esbuild, xterm.js (`@xterm/xterm` v5), node-pty (`@lydell/node-pty` v1), vanilla DOM (no UI framework).

**Testing vault:** `/Users/pavel/obsidian-test`. **All testing (CDP, install.sh, manual verification) MUST target this vault only — NEVER the main vault `/Users/pavel/obsidian-notes`.** The main vault is production; breaking it with experimental plugin changes is unacceptable.

### Architecture

```
src/main.ts          — Plugin entry: register view, ribbon icon, command
src/TerminalView.ts  — ItemView subclass, owns xterm.js Terminal + FitAddon (DOM renderer)
src/PtyBridge.ts     — node-pty wrapper: spawn $SHELL, pipe data between PTY and xterm
```

Data flow: `xterm.onData → pty.write → shell → pty.onData → xterm.write`

### Known pitfall: xterm.js vs Obsidian CSS

Obsidian applies global CSS rules (line-height, font, display) to ALL DOM elements including `<span>`. xterm.js DOM renderer creates `<span>` per character — Obsidian CSS shifts these off the internal coordinate grid, breaking selection alignment.

**Defense:** `user-select: none` on all terminal elements blocks **browser DOM selection** (full-width blue rectangles). xterm.js uses its own SelectionManager — not affected by `user-select: none`.

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
### Keyboard shortcuts

| Shortcut | Context | Action |
|----------|---------|--------|
| `Ctrl+C` | Has selection | Copy selection to clipboard |
| `Ctrl+C` | No selection | Send SIGINT (`\x03`) to shell |
| `Ctrl+V` | Any | Paste from clipboard |
| `Ctrl+Shift+C` | Any | Copy selection to clipboard |
| `Ctrl+Shift+V` | Any | Paste from clipboard |
| `Right-click` | Terminal | Paste from clipboard |

**Design note:** Paste is handled synchronously via `e.clipboardData.getData('text/plain')` in a capture-phase listener on the `<textarea>`. `stopImmediatePropagation()` prevents xterm.js from also processing the event. Single code path, no async `readText()`, no double paste. Copy uses `preventDefault` on the `copy` event to block xterm.js's duplicate handler.

- PTY process must be killed in `onClose()` to avoid zombie shells
- node-pty native addon must match Obsidian's Electron ABI — use `@lydell/node-pty` for better prebuild coverage
- Build artifacts (`.zip`, bundles, installers) go to `build/` — never to repo root. Both `build/` and `*.zip` are in `.gitignore`.

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
- `/Users/pavel/obsidian-test` → Obsidian vault (external data)
- `~/.claudocker/local` → `/home/dev/.claudocker-persist` (persistent container storage)

### Custom Skills

| Skill | Description |
|---|---|
| `mounts` | Show mounted directories configured for claudocker |
| `terminal-debug` | Automated Obsidian testing via CDP (eval JS, screenshots, pixel analysis) |
| `screenshot-debug` | Screenshot → pixel analysis → diagnosis loop for visual bugs |

## Knowledge Base

Non-obvious problems and solutions are documented in `autodocs/knowledge-base/`. When you discover a new problem, create a file using the template `autodocs/knowledge-base/template.md`.

**Important:** when adding a new finding, add cross-references `[[related-key]]` to existing KB files.

Current findings:
- [[obsidian-css-overrides-position]] — Obsidian resets CSS position to static
- [[electron-require-resolution]] — node-pty requires an absolute path in require()
- [[obsidian-steals-focus]] — Obsidian steals focus after opening an ItemView
- [[shell-login-interactive-nvm]] — nvm requires a login shell (-l -i)
- [[esbuild-native-modules-external]] — native modules must be external in esbuild
- [[cdp-remote-debugging]] — debugging via the Chrome DevTools Protocol

## Task Documentation

Tasks are documented in `autodocs/tasks/` using the template `autodocs/tasks/template.md`. Filename format: `YYYY-MM-DD--task-slug.md`.

**When to create a task:**
- A new feature affecting >1 file
- A non-trivial bug requiring investigation
- An architectural decision with several options
- Before starting a major refactoring

**Effort estimate in tokens** (field `Estimate`):
- **S (~5k)** — a small fix, one edit in one file
- **M (~20k)** — a feature/bug in 2-3 files, a little research
- **L (~50k)** — a large feature, several iterations, affects the architecture
- **XL (~100k+)** — an epic, requires design, multiple PRs, can be split into subtasks

**Workflow:**
1. Create a task file from the template, fill in Overview and Design
2. Align the plan with the user (if needed)
3. During work: mark Completed, update Remaining
4. On completion: mark all `[x]` in Definition of Done, Status → done, commit

**Related KB files and tasks** are linked via `[[wikilink]]`.

## Ideas

Ideas are stored in `autodocs/ideas/` using the template `autodocs/ideas/template.md`. Filename format: `YYYY-MM-DD--idea-slug.md`.

**When to create an idea:**
- You came up with a feature but aren't sure it's needed — you don't want to file a task right away
- You saw a problem, but the solution isn't obvious yet
- You want to capture a "what if…" thought without committing to implementation

**Statuses:**
- `idea` — a raw thought, not deeply considered
- `exploring` — investigating, reading code, checking feasibility
- `planned` — idea accepted, a task was created in `autodocs/tasks/` (add a link in `Related`)
- `discarded` — rejected (with the reason noted in Notes)

**Workflow:**
1. Caught a thought → create a file from the template, status `idea`
2. Decided to dig deeper → status `exploring`, fill in Risks / unknowns
3. Idea accepted → status `planned`, create a task, add cross-references
4. Idea rejected → status `discarded`, record the reason in Notes

**Related tasks and KB** are linked via `[[wikilink]]` in the `Related` field.

## Screenshot Analysis Workflow

When the user shares a screenshot (usually saved to `screenshots/` in the project):

1. **Analyze first, then speak.** Use Python/Pillow to extract pixel data: luminance heatmap, blue selection regions, text row positions, selection-to-text alignment. Never guess — read the pixels.

2. **Report findings before proposing fixes.** Describe what the screenshot shows in concrete terms: where are the selection blocks? Where is the text? Do they overlap? Are there ghosts/duplicates?

3. **Propose ranked options with rationale.** Each option must explain why it's better than previous failed attempts. Reference specific commits that were tried and why they didn't work.

4. **Wait for user approval before making ANY code changes.** User selects an option → then implement.

5. **After each attempt, update `autodocs/archive/knowledge-base/selection-fix-log.md`.** Add a new row to the attempts table: attempt number, commit hash, what was changed, why it should work, result (what the screenshot showed), why it didn't work, and screenshot number. Keep the Root Cause Hypothesis section updated with the current best theory.
