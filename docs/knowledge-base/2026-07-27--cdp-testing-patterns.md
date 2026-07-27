# CDP Testing Patterns & Automation Coverage

**Дата:** 2026-07-27
**Статус:** resolved
**Связано:** [[cdp-remote-debugging]]

## Symptoms

Нужно тестировать плагин без ручного вмешательства. CDP позволяет выполнять JS в контексте Obsidian, читать DOM, вызывать функции — но не всё работает как ожидается.

## Patterns: What Works

### 1. Plugin state manipulation (`settings`, `saveSettings`, module functions)
```js
var pl = app.plugins.plugins["obsidian-terminal"];
pl.settings.shell = "/bin/zsh";
pl.saveSettings();
pl.syncTerminalShell();
pl.openTerminal();
```
✅ Надёжно. Можно гонять полный цикл: настройка → spawn → проверка.

### 2. DOM inspection after Settings Tab open
```js
app.setting.open();
app.setting.openTabById("obsidian-terminal");
var select = app.setting.contentEl.querySelector("select");
// select.value === selected shell
// select.options — все опции
```
✅ Работает. Settings Tab можно открыть и читать программно.

### 3. Dropdown selection via `dispatchEvent("change")`
```js
select.value = "__custom__";
select.dispatchEvent(new Event("change", { bubbles: true }));
```
✅ Срабатывает. Obsidian обрабатывает change на `<select>`, перерисовывает UI.

### 4. Direct function call instead of UI simulation
```js
// Вместо симуляции ввода текста — вызываем функцию напрямую
var fs = require("fs");
fs.accessSync("/bin/zsh", fs.constants.X_OK);
// Проверяем borderColor, title на input элементе
```
✅ Надёжнее, чем симуляция событий.

### 5. Terminal buffer reading
```js
var v = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
v.pty.write("echo $SHELL\n");
// Читаем:
var buf = v.term.buffer.active;
buf.getLine(i).translateToString(true);
```
✅ End-to-end: открыл терминал → послал команду → прочитал вывод.

### 6. Focus verification
```js
document.activeElement === input  // true/false
```
✅ После `input.focus()` можно проверить.

## Anti-Patterns: What Doesn't Work

### ❌ `dispatchEvent("input")` не триггерит Obsidian Setting.onChange
```js
input.value = "/bin/zsh";
input.dispatchEvent(new Event("input", { bubbles: true }));
// onChange НЕ вызывается
```
**Workaround:** вызывать валидацию напрямую (`validateAndShow(inputEl, path)`) или тестировать через манипуляцию `plugin.settings` + проверку конечного результата (терминал открылся с нужным shell).

### ❌ `const` и `let` переменные липнут между eval-вызовами
```js
// Вызов 1:
var p = ...;  // OK
// Вызов 2:
var p = ...;  // SyntaxError: Identifier 'p' has already been declared
```
**Workaround:** всегда использовать IIFE `(function() { ... })()`.

## Automation Coverage

Цель: 100% DoD-пунктов должны проверяться без ручного вмешательства.

| Слой | Покрытие | Как |
|------|---------|-----|
| Settings (чтение/запись) | 100% | `plugin.settings` + `saveSettings()` |
| Settings Tab DOM | 90% | `app.setting.open()` + querySelector |
| Settings Tab input | 80% | Прямой вызов валидации + DOM-проверка |
| Shell detection | 100% | `require("fs")` из CDP |
| Terminal spawn | 100% | `openTerminal()` + `pty.write()` + buffer read |
| Focus behaviour | 90% | `input.focus()` + `document.activeElement` |
| CSS/rendering | 70% | Скриншот через `cdp-screenshot.py` |

**Текущий общий:** ~85%. Осталось: симуляция набора текста в Setting.addText (можно закрыть прямым вызовом onChange после извлечения колбэка из компонента).

## Как найти в коде

- `scripts/cdp-eval.py` — выполнение JS через CDP
- `scripts/cdp-screenshot.py` — скриншоты
- `grep -r "dispatchEvent\|validateAndShow\|openTabById" src/`
- KB: [[cdp-remote-debugging]]
