# Dev Kit

Инструменты разработчика для отладки и тестирования Obsidian Terminal.

## Структура

```
dev-kit/
├── README.md              # Этот файл
├── debug/                 # Запуск Obsidian с CDP + отладка
│   ├── debug.bat          # Windows: launch Obsidian + CDP, portproxy, firewall (batch, без PowerShell)
│   └── debug.py           # Python: единый CDP-клиент (test, screenshot, eval, view)
├── cdp/                   # CDP-скрипты (Chrome DevTools Protocol)
│   ├── cdp-eval.py        # Выполнить JavaScript в Obsidian через CDP
│   └── cdp-screenshot.py  # Скриншот Obsidian через CDP (Page.captureScreenshot)
└── cdp-testing.md         # Документация: как работает CDP-тестирование
```

## Быстрый старт

### 1. Запустить Obsidian с CDP

**Windows:**
```cmd
dev-kit\debug\debug.bat C:\Users\tania\Documents\obsidian-test
```
Скрипт сам найдёт Obsidian.exe, запустит его с `--remote-debugging-port`, настроит portproxy и firewall.

**macOS (вручную):**
```bash
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*
```

### 2. Проверить соединение

```bash
CDP_HOST=192.168.1.144 python3 dev-kit/debug/debug.py test
# или локально:
python3 dev-kit/debug/debug.py test --local
```

### 3. Выполнить JS в Obsidian

```bash
python3 dev-kit/cdp/cdp-eval.py 'app.plugins.plugins["obsidian-terminal"]'
```

### 4. Сделать скриншот

```bash
python3 dev-kit/cdp/cdp-screenshot.py              # автоимя (N.png)
python3 dev-kit/cdp/cdp-screenshot.py my-test.png  # конкретное имя
```

Скриншоты сохраняются в `screenshots/` (gitignored, runtime-only).

## debug.py — универсальный клиент

```bash
python3 dev-kit/debug/debug.py test              # health check (TCP → CDP → JS eval)
python3 dev-kit/debug/debug.py view              # показать все CDP-таргеты
python3 dev-kit/debug/debug.py eval '<js>'       # выполнить JavaScript
python3 dev-kit/debug/debug.py screenshot        # скриншот (автоимя)
python3 dev-kit/debug/debug.py screenshot x.png  # скриншот (конкретное имя)
```

Аргументы:
- `--local` — использовать 127.0.0.1 вместо `CDP_HOST`
- `CDP_HOST` (env) — IP удалённой машины (по умолчанию 127.0.0.1)
- `CDP_PORT` (env) — порт (по умолчанию 9222)
- `CDP_VAULT` (env) — фильтр по имени vault
- `CDP_TIMEOUT` (env) — таймаут в секундах (по умолчанию 15)

## cdp-eval.py — выполнить JS

```bash
python3 dev-kit/cdp/cdp-eval.py 'navigator.platform'

# Перезагрузить плагин
python3 dev-kit/cdp/cdp-eval.py '
  app.plugins.disablePlugin("obsidian-terminal");
  await new Promise(r => setTimeout(r, 300));
  app.plugins.enablePlugin("obsidian-terminal");
'

# Открыть терминал
python3 dev-kit/cdp/cdp-eval.py '
  let leaf = app.workspace.getLeaf("split", "horizontal");
  await leaf.setViewState({ type: "obsidian-terminal-view", active: true });
  app.workspace.revealLeaf(leaf);
'
```

Переменные окружения те же: `CDP_HOST`, `CDP_PORT`, `CDP_VAULT`.

## cdp-screenshot.py — скриншот

```bash
python3 dev-kit/cdp/cdp-screenshot.py              # screenshots/N.png
python3 dev-kit/cdp/cdp-screenshot.py via-eval.png # screenshots/via-eval.png
```

## Связанные ресурсы

- [CLAUDE.md](../CLAUDE.md) — архитектура плагина, билд, ограничения
- [cdp-testing.md](./cdp-testing.md) — как работает CDP-тестирование
- [autodocs/knowledge-base/](../autodocs/knowledge-base/) — KB неочевидных проблем
- `.claude/skills/terminal-debug/` — Claude skill для CDP-отладки
- `.claude/skills/screenshot-debug/` — Claude skill для визуальной диагностики
