# CDP Testing

Автоматизированное тестирование плагина через Chrome DevTools Protocol из Docker-контейнера.

## Как это работает

Obsidian работает на Electron (Chromium), который поддерживает [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/). Включаем удалённую отладку флагом `--remote-debugging-port`, и из контейнера подключаемся к Obsidian через WebSocket — выполняем JavaScript, снимаем скриншоты, анализируем DOM.

```
┌─────────────────────────────────────────────────┐
│ macOS host                                       │
│  ┌──────────────────────────────────────────┐   │
│  │ Obsidian (Electron)                       │   │
│  │  CDP Server on 127.0.0.1:9222            │   │
│  └──────────────────────────────────────────┘   │
│                     ↑                            │
│                     │ host.docker.internal        │
│                     │ (192.168.65.254:9222)       │
├─────────────────────┼───────────────────────────┤
│ Docker container    │                            │
│  ┌──────────────────┴───────────────────────┐   │
│  │ scripts/cdp-eval.py                      │   │
│  │ scripts/cdp-screenshot.py                │   │
│  │  ↓                                       │   │
│  │  Raw WebSocket → CDP → JS execution      │   │
│  │  → DOM queries / screenshots             │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

## Запуск Obsidian с отладкой

```bash
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*
```

- `--remote-debugging-port=9222` — порт CDP сервера
- `--remote-allow-origins=*` — разрешает WebSocket-подключения с любого origin (нужно для Docker)
- Используем `open -a` с `--args`, а не прямой запуск бинарника — иначе Obsidian включает CLI-режим

После запуска DevTools слушает на `ws://127.0.0.1:9222`.

## Инструменты

### `scripts/cdp-eval.py`

Выполняет JavaScript в контексте Obsidian и возвращает результат.

```bash
python3 scripts/cdp-eval.py '<javascript expression>'
```

**Примеры:**

```bash
# Проверка соединения
python3 scripts/cdp-eval.py "'hello from obsidian!'"

# DOM-диагностика
python3 scripts/cdp-eval.py '
  JSON.stringify({
    screen: document.querySelector(".xterm-screen")?.className,
    selectionPos: getComputedStyle(document.querySelector(".xterm-selection")).position
  })
'

# Действия с плагином
python3 scripts/cdp-eval.py '
  app.plugins.disablePlugin("obsidian-terminal");
  app.plugins.enablePlugin("obsidian-terminal");
  "reloaded"
'

# Открыть терминал
python3 scripts/cdp-eval.py '
  let leaf = app.workspace.getLeaf("split", "horizontal");
  leaf.setViewState({ type: "obsidian-terminal-view", active: true });
  "opened"
'

# Выделить текст в терминале
python3 scripts/cdp-eval.py '
  let view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
  view?.term?.selectLines(0, 3);
  "selected"
'
```

### `scripts/cdp-screenshot.py`

Делает скриншот окна Obsidian.

```bash
python3 scripts/cdp-screenshot.py            # авто-имя (следующий номер)
python3 scripts/cdp-screenshot.py test.png   # конкретное имя
```

Скриншоты сохраняются в `screenshots/`.

## Как устроены скрипты

Оба скрипта используют **raw WebSocket** (не `websocket-client`) — чтобы обойти проверку Origin заголовка. CDP принимает подключения только с `Origin: http://localhost:9222`, поэтому скрипты:

1. Делают HTTP GET на `http://host.docker.internal:9222/json` (с `Host: localhost`)
2. Находят страницу Obsidian (`app://obsidian.md/index.html`)
3. Открывают TCP-сокет, делают WebSocket handshake с правильным `Origin`
4. Отправляют CDP-команды (`Runtime.evaluate`, `Page.captureScreenshot`)
5. Парсят ответ

Контейнер видит хост через `host.docker.internal` → `192.168.65.254`.

## Типичный цикл отладки

```
1. Изменил код
   ↓
2. npm run build              ← собрал
   ↓
3. cdp-eval.py '...reload...' ← перезагрузил плагин
   ↓
4. cdp-eval.py '...open...'   ← открыл терминал
   ↓
5. cdp-eval.py '...select...' ← выделил текст
   ↓
6. cdp-screenshot.py          ← скриншот
   ↓
7. python3 -c "PIL анализ"     ← проверил пиксели
```

Всё без участия человека — не нужно кликать, перезагружать, выделять вручную.

## Ограничения

- **Origin check**: Electron по умолчанию принимает WebSocket только с `localhost`. Скрипты обходят это raw-сокетом с подменой заголовка `Origin`. Если флаг `--remote-allow-origins=*` работает в вашей версии Electron — ограничения нет.
- **Target ID меняется** при каждом перезапуске Obsidian. Скрипты автоматически получают актуальный ID из `/json`.
- **Только один Obsidian**: скрипты берут первую страницу `app://obsidian.md`, если открыто несколько окон — поведение не определено.
- **Скриншоты через Page.captureScreenshot** — только видимая область. Для полного скриншота нужно использовать расширения.
