---
name: terminal-debug
description: Отладка Minimalist Terminal через CDP — авто-тесты, скриншоты, анализ пикселей без ручных действий
user-invocable: true
---

# terminal-debug

Автоматизированная отладка плагина через Chrome DevTools Protocol. Скрипты `dev-kit/cdp/cdp-eval.py` и `dev-kit/cdp/cdp-screenshot.py` позволяют выполнять JS в Obsidian и делать скриншоты из контейнера.

## Запуск Obsidian с CDP

**macOS:**
```bash
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*
```

**Windows:**
```cmd
debug.bat "C:\Users\tania\Documents\obsidian-test"
```
Или вручную:
```cmd
"C:\Users\tania\AppData\Local\Obsidian\Obsidian.exe" --remote-debugging-port=9222 "C:\Users\tania\Documents\obsidian-test"
```
Важно: `--remote-debugging-address=0.0.0.0` не нужен для локального тестирования. Флаг `--remote-allow-origins=*` тоже опционален.

## Инструменты

### cdp-eval.py — выполнить JS

```bash
python3 dev-kit/cdp/cdp-eval.py '<expression>'
```

### cdp-screenshot.py — скриншот

```bash
python3 dev-kit/cdp/cdp-screenshot.py          # screenshots/N.png
python3 dev-kit/cdp/cdp-screenshot.py name.png # screenshots/name.png
```

## Часто используемые команды

### Перезагрузить плагин
```bash
python3 dev-kit/cdp/cdp-eval.py '
  app.plugins.disablePlugin("minimalist-terminal");
  await new Promise(r => setTimeout(r, 300));
  app.plugins.enablePlugin("minimalist-terminal");
'
```

### Открыть терминал
```bash
python3 dev-kit/cdp/cdp-eval.py '
  let leaf = app.workspace.getLeaf("split", "horizontal");
  await leaf.setViewState({ type: "minimalist-terminal-view", active: true });
  app.workspace.revealLeaf(leaf);
'
```

### Доступ к TerminalView и xterm
```js
let view = app.workspace.getLeavesOfType("minimalist-terminal-view")[0]?.view;
// view.term   — xterm.js Terminal
// view.pty    — PtyBridge
// view.container — HTMLElement контейнера
```

### Выделить текст через xterm API
```js
view.term.selectLines(0, 3);           // строки 0-2
view.term.selectAll();                 // весь буфер
view.term.getSelection();              // текст выделения
view.term.clearSelection();
```

### DOM-диагностика выделения
```js
let sel = document.querySelector(".xterm-selection");
let rows = document.querySelector(".xterm-rows");
JSON.stringify({
  selPos: getComputedStyle(sel).position,
  screenPos: getComputedStyle(document.querySelector(".xterm-screen")).position,
  diff: Math.round(sel.getBoundingClientRect().top - rows.getBoundingClientRect().top),
  selChildren: sel.childNodes.length,
  selectionDivStyles: Array.from(sel.childNodes).map(c => c.style.cssText)
});
```

### Пиксельный анализ скриншота
```python
from PIL import Image
img = Image.open('screenshots/N.png')
# терминал: #1e1e1e ≈ (30,30,30)
# выделение: #264f78 ≈ (38,79,120)
# текст:     #d4d4d4 ≈ (212,212,212)
```

## Проблемы и их симптомы

| Симптом | Вероятная причина | Что проверять |
|---------|------------------|---------------|
| Призрак выделения (два синих прямоугольника) | `.xterm-screen` потерял `position: relative` | `getComputedStyle(screen).position` |
| `$$$$` поверх текста | `.xterm-char-measure-element` потерял `visibility: hidden` | `getComputedStyle(measure).visibility` |
| Выделение не совпадает с текстом | `diff !== 0` между `.xterm-selection` и `.xterm-rows` | `getBoundingClientRect()` обоих слоёв |
| Текст не виден сквозь выделение | `background-color` сплошной, не rgba | `getComputedStyle(selDiv).backgroundColor` |

## Obsidian CSS-переопределения

Obsidian глобально сбрасывает `position` на `static` у многих элементов. xterm.js v5 DOM renderer требует:

- `.xterm-screen` — `position: relative` (containing block для selection)
- `.xterm-helpers` — `position: absolute; top: 0` (не занимать поток)
- `.xterm-char-measure-element` — `position: absolute; left: -9999em; visibility: hidden` (невидим)
- `.xterm-helper-textarea` — `position: absolute; opacity: 0; left: -9999em` (спрятан)

Все защиты в `styles.css` через `!important`.

## Тестирование Copy/Paste

### Проверка что paste не дублируется

**Правильный подход** — синтетические DOM-события (НЕ `Input.dispatchKeyEvent`):

```js
// 1. Шпионим за pty.write (не за readText — вызывает петлю!)
var v = app.workspace.getLeavesOfType("minimalist-terminal-view")[0]?.view;
var ow = v.pty.write.bind(v.pty);
var wc = 0;
v.pty.write = function(d) { wc++; return ow(d); };

// 2. Эмулируем Ctrl+V через keydown + paste события
var ta = v.term.element.querySelector("textarea");
ta.dispatchEvent(new KeyboardEvent("keydown", {
    key: "v", code: "KeyV", ctrlKey: true, shiftKey: false,
    bubbles: true, cancelable: true
}));
ta.dispatchEvent(new ClipboardEvent("paste", {
    bubbles: true, cancelable: true,
    clipboardData: new DataTransfer()
}));

// 3. Проверяем: wc должен быть 0 (наш handler не вызывает readText)
//    или 1 (если paste guard синхронно пишет)
JSON.stringify({writeCount: wc});
```

### Проверка что paste guard блокирует xterm.js

```js
var pasteFired = false;
ta.addEventListener("paste", function(e) { pasteFired = true; });
ta.dispatchEvent(new ClipboardEvent("paste", {
    bubbles: true, cancelable: true,
    clipboardData: new DataTransfer()
}));
// pasteFired должно быть false (guard stopImmediatePropagation)
```

### Проверка что Ctrl+C без выделения = SIGINT

```js
var ow = navigator.clipboard.writeText.bind(navigator.clipboard);
var wc = 0;
navigator.clipboard.writeText = function(d) { wc++; return ow(d); };
ta.dispatchEvent(new KeyboardEvent("keydown", {
    key: "c", code: "KeyC", ctrlKey: true, shiftKey: false,
    bubbles: true, cancelable: true
}));
navigator.clipboard.writeText = ow;
// wc должно быть 0 (не копирование, а SIGINT)
```

## Управление CDP-соединениями

**Критично:** каждое WebSocket-соединение надо закрывать. Иначе они накапливаются и блокируют новые.

### Паттерн: одно соединение на серию команд

```python
from debug import http_get, find_obsidian_page, ws_connect, ws_send, ws_recv
import json

page = find_obsidian_page(http_get('/json'), None)
sock = ws_connect(page, 15)

# Все команды через один сокет
for cmd in commands:
    ws_send(sock, cmd)
    result = ws_recv(sock)

sock.close()  # ← ОБЯЗАТЕЛЬНО
```

### Правила

1. **Одно соединение** для всей тестовой серии
2. **Всегда `sock.close()`** в конце
3. **Не создавать >5 соединений** за сессию
4. **После тестов — перезапуск Obsidian** для очистки
5. **Не использовать `debug.py eval` в цикле** — каждый вызов создаёт новое соединение

### Что НЕ работает

- `Input.dispatchKeyEvent` для тестирования paste (даёт ложный double paste)
- Подмена `navigator.clipboard.readText` (вызывает рекурсивную петлю)
- `location.reload()` для перезагрузки плагина (Obsidian кеширует)
- `Page.captureScreenshot` без `Page.enable`
