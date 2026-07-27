# Fix Clipboard Copy — Browser DOM Selection Interference

**Created:** 2026-07-27
**Status:** in-progress
**Estimate:** S (~5k)
**Branch:** main

## Overview / Goal

`Ctrl+Shift+C` не копирует выделенный текст из терминала в буфер обмена при работе внутри claudocker. Выделение визуально отображается (синяя подсветка), но `term.getSelection()` возвращает пустую строку — браузерное DOM-выделение маскируется под xterm.js-выделение.

Корневая причина: в `styles.css` отсутствует `user-select: none` на контейнере терминала. Браузер создаёт своё DOM-выделение (визуально похожее на xterm.js), но `term.getSelection()` умеет читать только выделение xterm.js.

## Design

Три независимых улучшения:

1. **`user-select: none` на `.terminal-view-content`** — запрещает браузеру создавать DOM-выделение. xterm.js использует собственный SelectionManager (не браузерный), поэтому `user-select: none` на него не влияет.

2. **`e.code` вместо `e.key`** — проверка физической клавиши (`KeyC`/`KeyV`) вместо layout-зависимого символа (`"C"`/`"V"`). На русской раскладке `e.key === "C"` не срабатывает (приходит кириллическая `"С"`).

3. **Electron clipboard fallback** — `require('electron').clipboard.writeText()` пишет напрямую в системный буфер, надёжнее чем Web API `navigator.clipboard.writeText()` внутри Electron.

## Solution

### 1. CSS: блокировка браузерного выделения (`styles.css`)

```css
.terminal-view-content {
  user-select: none !important;
}
```

### 2. Keyboard: `e.code` вместо `e.key` (`TerminalView.ts`)

```typescript
// Было:
if (e.ctrlKey && e.shiftKey && e.key === "C")

// Стало:
if (e.ctrlKey && e.shiftKey && e.code === "KeyC")
```

### 3. Clipboard: Electron first, Web API fallback (`TerminalView.ts`)

```typescript
function writeClipboard(text: string): void {
  try {
    const { clipboard } = require("electron");
    clipboard.writeText(text);
    return;
  } catch {
    // not in Electron — fall back to Web API
  }
  navigator.clipboard.writeText(text).catch((err) => {
    console.error("Terminal: clipboard write failed:", err);
  });
}
```

### 4. Диагностика: Notice + контекстное меню (`TerminalView.ts`)

- `new Notice("Copied N chars")` при успешном копировании
- `new Notice("No selection to copy")` если `getSelection()` пуст
- Контекстное меню (правый клик) с Copy и Paste — альтернативный способ скопировать

## Implementation Plan

### 1. CSS fix — `user-select: none`
- **Done.** `styles.css` — добавлен `user-select: none !important` на `.terminal-view-content`

### 2. Keyboard layout fix — `e.code`
- **Done.** `TerminalView.ts` — заменены `e.key === "C"/"V"` на `e.code === "KeyC"/"KeyV"`

### 3. Clipboard reliability — Electron fallback
- **Done.** `TerminalView.ts` — функция `writeClipboard()`: Electron → Web API

### 4. Diagnostics — Notice + context menu
- **Done.** `TerminalView.ts` — Notice при copy/paste, кастомное контекстное меню

### 5. Убрать диагностику перед мержем
- **TODO.** Перед final merge: убрать Notice, оставить контекстное меню (полезная фича)

## Completed

- [x] CSS: `user-select: none` на `.terminal-view-content`
- [x] Keyboard: `e.code === "KeyC"/"KeyV"` вместо `e.key`
- [x] Clipboard: `writeClipboard()` с Electron fallback
- [x] Diagnostics: Notice + контекстное меню

## Remaining

- [ ] Тестирование: проверить, что `getSelection()` возвращает текст после `user-select: none`
- [ ] Тестирование: проверить `Ctrl+Shift+C` копирование с claudocker
- [ ] Убрать `Notice` диагностику (оставить только контекстное меню)

## Definition of Done

- [ ] `Ctrl+Shift+C` копирует выделенный текст из терминала (в т.ч. с claudocker)
- [ ] `Ctrl+Shift+V` вставляет из буфера
- [ ] Правый клик → Copy работает при наличии выделения
- [ ] Правый клик → Paste работает
- [ ] Браузерное DOM-выделение не появляется в терминале
- [ ] Не сломано обычное выделение xterm.js (синяя подсветка, точное попадание в символы)
- [ ] Diagnostics (Notice) убраны из финальной версии
- [ ] Билд проходит без ошибок

## Open Questions

- [ ] Почему проблема проявляется именно с claudocker, а не с обычным шеллом?
  - Гипотеза: в обычном шелле браузерное выделение тоже есть, но пользователь реже пытается копировать
  - Или: claudocker выводит что-то, что провоцирует браузер на создание DOM-выделения
  - Нужно проверить после фикса: исчезло ли выделение xterm.js вместе с браузерным?

## Patch

```bash
# Stash all changes (clipboard fix + pre-existing PtyBridge/main.ts changes):
git stash push -m "clipboard-fix: user-select none + e.code + Electron clipboard fallback"

# Apply later:
git stash apply stash@{N}
```
