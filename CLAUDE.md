# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Obsidian Terminal** — a minimal Obsidian plugin that embeds a real bash terminal into the workspace. UX modelled after IntelliJ IDEA's terminal: ribbon icon + Command Palette entry, terminal opens as a bottom pane.

Tech stack: TypeScript, esbuild, xterm.js (`@xterm/xterm` v5), node-pty (`@lydell/node-pty` v1), vanilla DOM (no UI framework).

The Obsidian vault for dev testing is mounted at `/Users/pavel/obsidian-test`.

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
- `/Users/pavel/obsidian-test` → Obsidian vault (external data)
- `~/.claudocker/local` → `/home/dev/.claudocker-persist` (persistent container storage)

### Custom Skills

| Skill | Description |
|---|---|
| `mounts` | Show mounted directories configured for claudocker |
| `terminal-debug` | Automated Obsidian testing via CDP (eval JS, screenshots, pixel analysis) |
| `screenshot-debug` | Screenshot → pixel analysis → diagnosis loop for visual bugs |

## Knowledge Base

Неочевидные проблемы и решения документируются в `docs/knowledge-base/`. При обнаружении новой проблемы — создать файл по шаблону `docs/knowledge-base/template.md`.

**Важно:** при добавлении новой находки добавлять перекрёстные ссылки `[[related-key]]` на существующие файлы KB.

Текущие находки:
- [[obsidian-css-overrides-position]] — Obsidian сбрасывает CSS position на static
- [[electron-require-resolution]] — node-pty требует абсолютный путь в require()
- [[obsidian-steals-focus]] — Obsidian крадёт фокус после открытия ItemView
- [[shell-login-interactive-nvm]] — nvm требует login shell (-l -i)
- [[esbuild-native-modules-external]] — нативные модули должны быть external в esbuild
- [[cdp-remote-debugging]] — отладка через Chrome DevTools Protocol

## Task Documentation

Задачи документируются в `docs/tasks/` по шаблону `docs/tasks/template.md`. Формат имени файла: `YYYY-MM-DD--task-slug.md`.

**Когда создавать задачу:**
- Новая фича, затрагивающая >1 файл
- Нетривиальный баг, требующий исследования
- Архитектурное решение с несколькими вариантами
- Перед началом крупного рефакторинга

**Оценка сложности в токенах** (поле `Estimate`):
- **S (~5k)** — мелкий фикс, одна правка в одном файле
- **M (~20k)** — фича/баг в 2-3 файлах, немного исследования
- **L (~50k)** — крупная фича, несколько итераций, затрагивает архитектуру
- **XL (~100k+)** — эпик, требует дизайна, нескольких PR, может быть разбит на подзадачи

**Workflow:**
1. Создать файл задачи из шаблона, заполнить Overview и Design
2. Согласовать план с пользователем (если нужно)
3. В процессе: отмечать Completed, обновлять Remaining
4. По завершении: Status → done, закоммитить

**Связанные KB-файлы и задачи** линкуются через `[[wikilink]]`.

## Screenshot Analysis Workflow

When the user shares a screenshot (usually saved to `screenshots/` in the project):

1. **Analyze first, then speak.** Use Python/Pillow to extract pixel data: luminance heatmap, blue selection regions, text row positions, selection-to-text alignment. Never guess — read the pixels.

2. **Report findings before proposing fixes.** Describe what the screenshot shows in concrete terms: where are the selection blocks? Where is the text? Do they overlap? Are there ghosts/duplicates?

3. **Propose ranked options with rationale.** Each option must explain why it's better than previous failed attempts. Reference specific commits that were tried and why they didn't work.

4. **Wait for user approval before making ANY code changes.** User selects an option → then implement.

5. **After each attempt, update `docs/selection-fix-log.md`.** Add a new row to the attempts table: attempt number, commit hash, what was changed, why it should work, result (what the screenshot showed), why it didn't work, and screenshot number. Keep the Root Cause Hypothesis section updated with the current best theory.
