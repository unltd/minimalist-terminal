# CDP Testing Automation → 100%

**Created:** 2026-07-27
**Status:** ready
**Estimate:** S (~5k)
**Branch:** main
**Related:** [[2026-07-27--cdp-testing-patterns]]

## Overview / Goal

Довести долю DoD-пунктов, проверяемых агентом через CDP без участия человека, с ~85% до 100%.

Текущий разрыв: симуляция ввода текста в `Setting.addText` не триггерит Obsidian `onChange`. Всё остальное уже автоматизировано.

## Design

### Проблема: `dispatchEvent("input")` не вызывает колбэк

Obsidian `Setting.addText` использует собственный обработчик, который не реагирует на программный `input` event. Нужен способ:

**Вариант A — извлечь колбэк из DOM-элемента**
Obsidian хранит обработчик на input элементе. Можно попробовать:
```js
// Obsidian внутренности — найти listener
var listeners = getEventListeners(input); // Chrome DevTools API in console
listeners.input[0].listener.call(input, "test value");
```
Минус: `getEventListeners` доступен только в DevTools console, не через CDP Runtime.evaluate.

**Вариант B — вызвать onChange напрямую через ссылку на компонент**
```js
// Setting.addText возвращает callback-based API
// Сохранить ссылку на onChange при создании
```
Плюс: чисто. Минус: нужно модифицировать SettingsTab, чтобы экспонировать колбэк (debug only).

**Вариант C — KeyboardEvent симуляция**
```js
// Симулировать реальное нажатие клавиши вместо input event
input.dispatchEvent(new KeyboardEvent("keydown", { key: "z", bubbles: true }));
input.dispatchEvent(new KeyboardEvent("keypress", { key: "z", bubbles: true }));
input.dispatchEvent(new KeyboardEvent("keyup", { key: "z", bubbles: true }));
```
Плюс: не требует изменений в коде. Минус: может не сработать (Obsidian слушает не DOM-события, а свой internal event emitter).

**Вариант D — прямой вызов валидации + разделение логики**
Вынести валидацию из колбэка в отдельную функцию, тестировать её напрямую, UI-часть не тестировать:
```js
// Валидация — отдельно, тестируется
export function validateShellPath(path: string): ValidationResult { ... }

// UI-колбэк — не тестируем (доверяем Obsidian)
.onChange(async (value) => {
  const result = validateShellPath(value.trim());
  updateInputStyle(text.inputEl, result);
  ...
});
```
Плюс: архитектурно правильно, UI и логика разделены. Минус: требует рефакторинга SettingsTab.

### Рекомендация

**Вариант B** (экспонировать колбэк для CDP) + **Вариант D** (разделение логики/UI):

1. Вынести `validateShellPath()` как экспортируемую функцию в `settings.ts`
2. В SettingsTab добавить `(window as any).__cdp_onShellChange = (v: string) => { ... }` — debug-мостик
3. Через CDP: `window.__cdp_onShellChange("/bin/zsh")` → триггерит onChange
4. В production сборке debug-мостик tree-shaken

## Implementation Plan

### 1. Extract `validateShellPath()` → `settings.ts`
- `validateShellPath(path: string): { ok: boolean; message: string }`
- Использует `fs.accessSync` + `fs.statSync`
- Экспортируется, тестируется через CDP

### 2. CDP bridge in SettingsTab
- `(window as any).__cdp_shellOnChange = (value: string) => { ... }` 
- Вызывает тот же код, что и UI onChange
- Только в dev-режиме (или всегда — для тестирования)

### 3. Cover remaining DoD gaps
- Custom path validation: ✅ (validateShellPath)
- Shell not found error: ✅ (уже работает через settings.shell)
- Focus retention: ✅ (document.activeElement)

### 4. Update coverage metric
- Обновить KB [[2026-07-27--cdp-testing-patterns]] → 100%

## Definition of Done

- [ ] `validateShellPath()` вынесена в `settings.ts` и экспортируется
- [ ] CDP-мостик позволяет вызвать onChange извне
- [ ] Все DoD-пункты Shell Selection проверены через CDP (подтверждено логом)
- [ ] KB [[2026-07-27--cdp-testing-patterns]] обновлён → coverage 100%

## Open Questions

- [ ] Стоит ли оставлять CDP-мостик в production? Предлагаю: да (под `window.__cdp_...`), он безвредный и полезен для отладки у пользователей.
- [ ] Нужно ли это для всех Setting-компонентов или только для shell? Предлагаю: только shell сейчас, расширять по мере добавления настроек.

## Notes

- Текущий охват: ~85% (задокументировано в [[2026-07-27--cdp-testing-patterns]])
- Главный разрыв: `Setting.addText` onChange
- Побочные: CSS/rendering verification (скриншоты уже работают)
