# Multi-Session Terminal Support

**Created:** 2026-07-20
**Status:** done
**Depends on:** [[obsidian-terminal-mvp]]

## Goal

Каждое нажатие на иконку терминала создаёт новый независимый терминал в отдельной вкладке. У каждого своя PTY-сессия, свой рабочий каталог, независимый shell-процесс.

## Design

**Variant A — flat tabs:** каждый терминал = отдельный WorkspaceLeaf в нижнем pane. Нативный Obsidian UX: табы в заголовке панели, переключение кликом.

Позже можно расширить до Variant C: кнопки `[+]` и `[×]` в заголовке, хоткеи для переключения.

## Implementation

### 1. `main.ts` — всегда создавать новый leaf

```typescript
// Было: переиспользовать первый существующий
let leaf = workspace.getLeavesOfType(VIEW_TYPE_TERMINAL)[0];
if (!leaf) { leaf = workspace.getLeaf("split", "horizontal"); ... }

// Стало: всегда новый
const existing = workspace.getLeavesOfType(VIEW_TYPE_TERMINAL);
if (existing.length >= MAX_TERMINALS) {
  workspace.revealLeaf(existing[existing.length - 1]); // фокус на последний
  return;
}
let leaf: WorkspaceLeaf;
if (existing.length > 0) {
  // Новая вкладка рядом с существующими терминалами
  const parent = existing[0].parent;
  leaf = workspace.createLeafInParent(parent, (parent as any).children.length);
} else {
  // Первый терминал: создаём нижнюю панель
  leaf = workspace.getLeaf("split", "horizontal");
}
await leaf.setViewState({ type: VIEW_TYPE_TERMINAL, active: true });
workspace.revealLeaf(leaf);
```

**Важно:** `workspace.createLeafInParent(parent, index)` создаёт **таб** (не новый сплит). Без этого каждый терминал открывался бы на отдельном уровне вместо соседней вкладки.

### 2. `TerminalView.ts` — уникальные имена + лимит

```typescript
export const MAX_TERMINALS = 10;

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

### 3. Закрытие — только свой leaf

```typescript
// Было: закрывало ВСЕ терминалы
onExit: () => {
  this.app.workspace.detachLeavesOfType(VIEW_TYPE_TERMINAL);
},

// Стало: закрывает только текущий
onExit: () => {
  this.leaf.detach();
},
```

Каждый лист закрывается независимо. `WorkspaceLeaf.detach()` — публичный метод Obsidian API.

## Resolved questions

- [x] При закрытии Terminal 1 и открытии нового — нумерация продолжается (Terminal 4). Переиспользование «дырок» не делаем — это стандартное поведение IDE.
- [x] Лимит на количество терминалов: **10** (`MAX_TERMINALS` в `TerminalView.ts`). При превышении фокусирует последний существующий.
- [x] Табы, не сплиты: `createLeafInParent()` вместо `getLeaf("split")` для последующих терминалов.

## CDP Testing results (2026-07-22)

```bash
# 1. Имена: Terminal 1, Terminal 2, Terminal 3
python3 scripts/cdp-eval.py '
  app.workspace.getLeavesOfType("obsidian-terminal-view")
    .map(l => l.view?.getDisplayText())
'
# → ["Terminal 1", "Terminal 2", "Terminal 3"]

# 2. Изоляция PTY: export FOO=AAA в T1 → echo $FOO в T2 → []
# PASS: переменная не видна

# 3. Независимое закрытие: exit в T2 → T1 и T3 остались
# PASS: 3 → 2 листа

# 4. Лимит 10: 15 вызовов open-terminal → 10 терминалов
# PASS: count=10

# 5. Табы, не сплиты: все листья в одном parent
# PASS: sameParent=true
```

## Notes

- Патч `docs/tasks/patches/2026-07-20--multi-session.patch` содержит баги (onExit закрывает все листья, не реализован `createLeafInParent`). Оставлен для истории, не применять.
- Реальная реализация отличается от патча в трёх местах: `createLeafInParent`, `leaf.detach()`, лимит.
