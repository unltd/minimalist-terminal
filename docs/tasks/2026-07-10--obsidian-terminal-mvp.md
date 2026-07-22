# Obsidian Terminal — MVP

**Created:** 2026-07-20
**Status:** done
**Branch:** main

## Overview

Build a minimal Obsidian plugin that embeds a real bash terminal with IntelliJ IDEA-like UX.

## MVP Constraints

- **Target machine:** MacBook Air 2014 (4GB RAM, Intel HD 5000, macOS Big Sur)
- **Obsidian version:** 1.5.0+
- **Performance:** терминал должен работать без заметных лагов на этом железе
- **Scope:** только DOM-рендерер (Canvas/WebGL — не для MVP)

## Definition of Done

- [x] Плагин собирается и загружается в Obsidian на MacBook Air 2014 → `tests/specs/mvp/build-load.spec` (4/4 PASS)
- [x] Терминал открывается по иконке и через Command Palette → `tests/specs/mvp/open-terminal.spec` (3/3 PASS)
- [x] Shell работает: команды выполняются, вывод отображается → `tests/specs/mvp/shell-exec.spec` (3/3 PASS)
- [x] Выделение текста мышью работает корректно → `tests/specs/mvp/selection.spec` (3/3 PASS)
- [x] Скролл работает → `tests/specs/mvp/scroll.spec` (2/2 PASS)
- [x] Авто-фокус при открытии → `tests/specs/mvp/autofocus.spec` (2/2 PASS)
- [x] Закрытие по Ctrl+D (exit) не оставляет зомби-процессов → `tests/specs/mvp/close-no-zombie.spec` (2/2 PASS)

## Completed

### Base terminal (2026-07-18)
- [x] Plugin skeleton: `main.ts`, `TerminalView.ts`, `PtyBridge.ts`
- [x] xterm.js v5 with DOM renderer + FitAddon
- [x] node-pty (@lydell/node-pty) for PTY — absolute path require() in Electron renderer
- [x] Shell: login+interactive flags for nvm PATH
- [x] Ribbon icon + Command Palette entry
- [x] Clipboard: Ctrl+Shift+C/V, right-click paste
- [x] Resize handling (ResizeObserver → fit + pty.resize)
- [x] Close on exit (Ctrl+D → detachLeaves)

### Selection fix (2026-07-20)
- [x] Root cause: Obsidian CSS overrides `position` to `static` on xterm.js elements
- [x] Protect `.xterm-screen` (position:relative), `.xterm-helpers` (absolute), `.xterm-viewport` (absolute+scroll)
- [x] Protect `.xterm-char-measure-element` (off-screen), `.xterm-helper-textarea` (hidden)
- [x] Semi-transparent selection: rgba(38,79,120,0.4) on selection divs
- [x] 17 → 1 squashed commit: `cf016c0`

### Scroll fix (2026-07-20)
- [x] `.xterm-viewport` was static+visible → protected with absolute+overflow-y:scroll

### Auto-focus (2026-07-20)
- [x] Obsidian steals focus after view open → retry loop (60×50ms) + mousedown capture

### Dev tooling (2026-07-20)
- [x] CDP: `scripts/cdp-eval.py` + `scripts/cdp-screenshot.py`
- [x] Skill: `.claude/skills/terminal-debug/`
- [x] Knowledge base: `docs/knowledge-base/` (6 entries + template)
- [x] Git: squashed selection commits, clean history

## Remaining

### Bugs
- [ ] `Cmd+R` / Hot Reload — Obsidian не подхватывает изменения CSS без ручного disable/enable плагина
- [ ] Переключение между листьями терминала сбрасывает фокус (mousedown listener помогает, но не всегда)
- [ ] xterm `.focus` класс не добавляется при программном `focus()` — курсор может не мигать

### Features
- [ ] **Multi-session** — несколько независимых терминалов (см. `docs/tasks/2026-07-20--multi-session.md`)
- [ ] Кнопка `[+]` в заголовке панели для быстрого создания терминала
- [ ] Ctrl+Tab / Ctrl+` для переключения между терминалами
- [ ] Опция закрыть терминал по `exit` только если один лист (сейчас всегда закрывает)
- [ ] Настройки: font size, theme, scrollback, default shell
- [ ] Индикатор в табе: текущая директория или запущенная команда
- [ ] Поддержка Canvas/WebGL рендерера (производительность)
- [ ] Автодополнение (Tab) поверх Obsidian — может конфликтовать с хоткеями

### Polish
- [ ] Анимация открытия (сейчас мгновенно)
- [ ] Терминал в боковой панели (left/right sidebar)
- [ ] Сохранение сессий между перезапусками Obsidian (tmux/screen интеграция?)

## Architecture notes

```
src/main.ts          — Plugin: registerView, ribbon, command
src/TerminalView.ts  — ItemView: xterm Terminal + FitAddon
src/PtyBridge.ts     — node-pty: spawn, pipe, kill
styles.css           — xterm.js CSS protection + terminal styling
```

Key constraints:
- CommonJS format, esbuild external: obsidian, electron, @lydell/node-pty, node builtins
- Desktop only (node-pty native addon)
- DOM renderer (Canvas/WebGL addons available but not loaded)

## CDP workflow

```bash
# Start Obsidian
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*

# Test cycle (from container)
python3 scripts/cdp-eval.py '<js>'
python3 scripts/cdp-screenshot.py
```

See `docs/cdp-testing.md` and `/terminal-debug` skill for details.

## Recent commits

```
96a7466 feat: auto-focus terminal on open
69cd84f Fix: protect xterm-viewport from Obsidian CSS overrides
cf016c0 Fix: xterm.js selection rendering in Obsidian (17→1 squashed)
```
