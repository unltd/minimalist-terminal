# Multi-Session Terminal Support

**Created:** 2026-07-20
**Status:** ready (patch prepared)
**Depends on:** [[obsidian-terminal-mvp]]

## Goal

Каждое нажатие на иконку терминала создаёт новый независимый терминал в отдельной вкладке. У каждого своя PTY-сессия, свой рабочий каталог, независимый shell-процесс.

## Design

**Variant A — flat tabs:** каждый терминал = отдельный WorkspaceLeaf в нижнем pane. Нативный Obsidian UX: табы в заголовке панели, переключение кликом.

Позже можно расширить до Variant C: кнопки `[+]` и `[×]` в заголовке, хоткеи для переключения.

## Implementation plan

### 1. `main.ts` — всегда создавать новый leaf

```typescript
// Было: переиспользовать первый существующий
let leaf = workspace.getLeavesOfType(VIEW_TYPE_TERMINAL)[0];
if (!leaf) { leaf = workspace.getLeaf("split", "horizontal"); ... }

// Стало: всегда новый
const leaf = workspace.getLeaf("split", "horizontal");
await leaf.setViewState({ type: VIEW_TYPE_TERMINAL, active: true });
```

### 2. `TerminalView.ts` — уникальные имена

```typescript
// Module-level counter
let nextTerminal = 1;

export class TerminalView extends ItemView {
  private readonly terminalNumber: number;

  constructor(leaf: WorkspaceLeaf) {
    super(leaf);
    this.terminalNumber = nextTerminal++;
  }

  getDisplayText(): string {
    return `Terminal ${this.terminalNumber}`;
  }
}
```

Terminal 1, Terminal 2, ... — Obsidian показывает в заголовке листа.

### 3. Закрытие — уже работает

`onClose()` убивает PTY текущего терминала. Каждый лист закрывается независимо.

## Patch

Готовый патч: `docs/tasks/patches/2026-07-20--multi-session.patch`

Применить:
```bash
git am docs/tasks/patches/2026-07-20--multi-session.patch
```

## Open questions

- [ ] При закрытии Terminal 1 и открытии нового — нумерация продолжается (Terminal 4) или переиспользуется (Terminal 1)?
  - Сейчас: продолжается (nextTerminal только растёт). Можно сделать `Math.max(...существующие номера) + 1`.
- [ ] Нужен ли лимит на количество терминалов?
- [ ] Как показывать в табе полезную информацию (cwd, последняя команда)?

## Testing

```bash
# Открыть 3 терминала и проверить имена
python3 scripts/cdp-eval.py '
  let names = app.workspace.getLeavesOfType("obsidian-terminal-view")
    .map(l => l.view?.getDisplayText());
  JSON.stringify(names); // ["Terminal 1", "Terminal 2", "Terminal 3"]
'
```
