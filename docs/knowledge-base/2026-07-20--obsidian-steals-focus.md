# Obsidian крадёт фокус после открытия ItemView

**Дата:** 2026-07-20
**Статус:** worked-around
**Связано:** [[obsidian-css-overrides-position]]

## Симптомы

`this.term.focus()` вызывается в `onOpen()`, но после открытия вьюшки терминала клавиатурный ввод идёт не в терминал. `document.activeElement === document.body`.

Прямой вызов `term.focus()` из DevTools Console **работает** и фокус остаётся. Проблема только при первом открытии.

## Причина

Obsidian выполняет асинхронную инициализацию вьюшки **после** завершения `onOpen()`. В процессе инициализации Obsidian вызывает `focus()` на других элементах (body, редактор, первый leaf), перехватывая фокус у терминала.

Тайминг: события `focusin` показывают, что Obsidian фокусирует `.cm-content` (CodeMirror) через ~300-800ms после открытия, иногда позже.

`active-leaf-change` событие срабатывает, но фокус всё равно крадётся после него.

## Решение (воркэраунд)

Три механизма:

1. **Retry-цикл** — каждые 50ms вызывать `term.focus()` в течение 3 секунд после `onOpen`. Цикл не останавливается досрочно — всегда отрабатывает все 60 итераций.

2. **mousedown capture** на контейнере терминала — любой клик внутри возвращает фокус:

```typescript
this.container?.addEventListener("mousedown", () => {
  this.term?.focus();
}, { capture: true, passive: true });
```

3. **scheduleFit** — после resize тоже вызывает `focus()`.

```typescript
let focusTries = 0;
const maxFocusTries = 60; // 3 seconds
const tryFocus = () => {
  if (focusTries >= maxFocusTries || !this.term) return;
  focusTries++;
  this.term?.focus();
  setTimeout(tryFocus, 50);
};
setTimeout(tryFocus, 50);
```

**Почему воркэраунд:** идеальное решение — найти событие Obsidian, которое гарантированно срабатывает ПОСЛЕ всей инициализации. Пока такое не найдено, polling работает стабильно.

## Ссылки

- Obsidian API: `active-leaf-change` — не помогает, фокус крадётся позже
- Obsidian forum: других решений не найдено

## Как найти в коде

- `src/TerminalView.ts` → секция "Focus the terminal"
- `grep "tryFocus\|focusTries\|maxFocusTries" src/TerminalView.ts`
