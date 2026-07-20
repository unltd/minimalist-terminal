---
name: terminal-debug
description: Отладка Obsidian Terminal через CDP — авто-тесты, скриншоты, анализ пикселей без ручных действий
user-invocable: true
---

# terminal-debug

Автоматизированная отладка плагина через Chrome DevTools Protocol. Скрипты `scripts/cdp-eval.py` и `scripts/cdp-screenshot.py` позволяют выполнять JS в Obsidian и делать скриншоты из контейнера.

## Запуск Obsidian с CDP (на маке)

```bash
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*
```

## Инструменты

### cdp-eval.py — выполнить JS

```bash
python3 scripts/cdp-eval.py '<expression>'
```

### cdp-screenshot.py — скриншот

```bash
python3 scripts/cdp-screenshot.py          # screenshots/N.png
python3 scripts/cdp-screenshot.py name.png # screenshots/name.png
```

## Часто используемые команды

### Перезагрузить плагин
```bash
python3 scripts/cdp-eval.py '
  app.plugins.disablePlugin("obsidian-terminal");
  await new Promise(r => setTimeout(r, 300));
  app.plugins.enablePlugin("obsidian-terminal");
'
```

### Открыть терминал
```bash
python3 scripts/cdp-eval.py '
  let leaf = app.workspace.getLeaf("split", "horizontal");
  await leaf.setViewState({ type: "obsidian-terminal-view", active: true });
  app.workspace.revealLeaf(leaf);
'
```

### Доступ к TerminalView и xterm
```js
let view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
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
