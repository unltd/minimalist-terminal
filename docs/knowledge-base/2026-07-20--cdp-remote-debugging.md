# Отладка Obsidian плагина через Chrome DevTools Protocol

**Дата:** 2026-07-20
**Статус:** resolved
**Связано:** [[obsidian-css-overrides-position]]

## Симптомы

Нужно автоматизировать тестирование плагина: выполнять JS в контексте Obsidian, делать скриншоты, анализировать DOM — без ручных действий.

## Решение

Electron (на котором работает Obsidian) поддерживает [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/) через флаг `--remote-debugging-port`.

### Запуск Obsidian

```bash
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*
```

- `--remote-debugging-port=9222` — включает CDP-сервер
- `--remote-allow-origins=*` — разрешает WebSocket с не-localhost origin
- **Важно:** использовать `open -a` с `--args`, а не прямой вызов бинарника (Obsidian CLI перехватывает аргументы)

### Подключение из Docker-контейнера

Docker-контейнер видит хост через `host.docker.internal` → `192.168.65.254`.

CDP слушает на `ws://127.0.0.1:9222`, но с флагом `--remote-allow-origins=*` принимает подключения с любого IP.

**Проблема Origin:** без флага CDP принимает WebSocket только с `Origin: localhost`. Из контейнера Origin — `192.168.65.254`. Решение — raw WebSocket с подменой заголовка `Origin`.

### Инструменты

- `scripts/cdp-eval.py` — выполнить JS
- `scripts/cdp-screenshot.py` — скриншот

Оба используют raw WebSocket (не библиотеку) для обхода Origin-проверки.

### Типичный цикл

```
1. npm run build                         ← собрал
2. cdp-eval.py '...reload...'            ← перезагрузил плагин
3. cdp-eval.py '...open terminal...'     ← открыл терминал
4. cdp-eval.py 'term.selectLines(0,3)'   ← выделил текст
5. cdp-screenshot.py                     ← скриншот
6. python3 -c "PIL анализ"               ← проверил пиксели
```

## Ссылки

- [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/)
- [Electron --remote-debugging-port](https://www.electronjs.org/docs/latest/tutorial/devtools)
- Подробнее: `docs/cdp-testing.md`, `scripts/cdp-eval.py`
- Skill: `/terminal-debug`

## Как найти в коде

- `scripts/cdp-eval.py`
- `scripts/cdp-screenshot.py`
- `docs/cdp-testing.md` — полная документация
- `.claude/skills/terminal-debug/SKILL.md` — skill для Claude Code
