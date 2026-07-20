# Obsidian сбрасывает CSS-свойства на static

**Дата:** 2026-07-18
**Статус:** resolved
**Связано:** [[obsidian-css-user-select]], [[viewport-scroll-broken]], [[selection-ghost]], [[char-measure-visible]]

## Симптомы

DOM-элементы внутри плагина ведут себя так, будто CSS-правила не применяются:
- Абсолютно позиционированные элементы (`position: absolute`) рендерятся в нормальном потоке
- `overflow-y: scroll` не работает
- `visibility: hidden` игнорируется
- `left: -9999em` не смещает элемент за экран

В Obsidian Developer Console: `getComputedStyle(element).position === "static"`, хотя xterm.js CSS явно задаёт `position: absolute` / `position: relative`.

## Причина

Obsidian загружает глобальный `app.css`, который содержит селекторы общего назначения, переопределяющие CSS-свойства у сторонних элементов. Правила в `app.css` переопределяют:
- `position` → `static`
- `overflow` / `overflow-y` → `visible` / `auto`
- `visibility` → `visible`
- `display` → `block`
- `line-height` → `1.5` (Obsidian)
- `font-family` → наследует тему

Специфичность этих селекторов выше, чем у xterm.js классов (из-за каскада или `!important` в теме).

Затронутые xterm.js v5 элементы:
| Элемент | Должен быть | Obsidian даёт | Последствия |
|---------|------------|---------------|-------------|
| `.xterm-screen` | `position: relative` | `static` | Слой выделения позиционируется от `workspace-leaf-content` вместо экрана |
| `.xterm-helpers` | `position: absolute; top: 0` | `static` | Helpers занимает место в потоке, сдвигая строки |
| `.xterm-viewport` | `position: absolute; overflow-y: scroll` | `static; visible` | Скролл не работает, вывод уезжает за границы |
| `.xterm-char-measure-element` | `position: absolute; left: -9999em; visibility: hidden` | `static; visible` | Символы `$$$` видны поверх текста |
| `.xterm-helper-textarea` | `position: absolute; opacity: 0; left: -9999em` | `static; opacity: 1` | Текстареа видна в углу |

## Решение

В `styles.css` плагина добавлены защитные правила с `!important` для каждого затронутого элемента:

```css
.terminal-view-content .xterm-screen { position: relative !important; }
.terminal-view-content .xterm-helpers { position: absolute !important; top: 0 !important; }
.terminal-view-content .xterm-viewport { position: absolute !important; overflow-y: scroll !important; }
.terminal-view-content .xterm-char-measure-element { position: absolute !important; left: -9999em !important; visibility: hidden !important; }
.terminal-view-content .xterm-helper-textarea { position: absolute !important; opacity: 0 !important; }
```

Правила используют `.terminal-view-content` как родительский селектор для достаточной специфичности.

## Ссылки

- Похожая проблема: [xterm.js #993](https://github.com/xtermjs/xterm.js/issues/993) — getCoordsRelativeToElement не учитывает scrollTop родителей
- Obsidian forum: ["CSS overrides in plugins"](https://forum.obsidian.md/t/css-specificity-issues-in-plugins/)

## Как найти в коде

- `styles.css` — секция "Protect xterm.js positioning"
- `grep -r "!important" styles.css`
- `grep "position.*static\|overflow.*visible"` — найти ещё не защищённые элементы
- DevTools: `getComputedStyle(el).position === "static"` для подозрительного элемента
