# Gauge + pytest Test Plan for MVP

**Created:** 2026-07-20
**Status:** planned
**Effort:** M (~20k)
**Related:** [[2026-07-10--obsidian-terminal-mvp]] [[2026-07-20--mvp-test-plan]]

## What

Покрыть 7 пунктов Definition of Done из [[2026-07-10--obsidian-terminal-mvp|MVP]] формализованными тестами: Gauge-спецификации (`.spec`, Markdown, BDD-синтаксис) описывают *что* тестируем, а pytest-степы с `getgauge` — *как* (через CDP).

## Why

- Сейчас тестирование ad-hoc: ручной запуск `cdp-eval.py` с JS-сниппетами. Нет структуры, нельзя прогнать регресс одной командой
- Gauge даёт человекочитаемые спецификации на Markdown — порог входа ниже, чем у pytest-bdd или behave
- pytest — стандарт в Python-экосистеме, фикстуры идеально ложатся на управление Obsidian через CDP
- Каждый пункт DoD превращается в воспроизводимый формальный тест, а не в ручную проверку «на глаз»

## Rough sketch

```
tests/
├── manifest.json              — Gauge project (language: python)
├── env/default/
│   └── python.properties
├── specs/mvp/                 — 7 .spec-файлов
│   ├── build-load.spec        — сборка и загрузка плагина
│   ├── open-terminal.spec     — иконка + Command Palette
│   ├── shell-exec.spec        — выполнение команд
│   ├── selection.spec         — выделение мышью (CDP + скриншот)
│   ├── scroll.spec            — скролл (CDP + скриншот)
│   ├── autofocus.spec         — авто-фокус при открытии
│   └── close-no-zombie.spec   — Ctrl+D без зомби
├── step_impl/                 — pytest + getgauge
│   ├── conftest.py            — фикстуры: CDP-соединение, процесс Obsidian
│   └── test_*.py              — по одному на spec
└── README.md
```

**conftest.py** управляет жизненным циклом: запуск Obsidian с `--remote-debugging-port=9222`, ожидание загрузки, остановка после тестов. CDP-клиент — обёртка над `subprocess.run(["python3", "scripts/cdp-eval.py", js])`.

**Пример спецификации** (`shell-exec.spec`):

```gauge
## Выполнение команды и вывод
Tags: mvp, doD-3, cdp

* Открыть терминал
* Дождаться приглашения командной строки длительностью до 5 секунд
* Выполнить команду "echo hello"
* Вывод содержит "hello"
```

**Пример степа** (`test_shell_exec.py`):

```python
from getgauge.python import step

@step('Выполнить команду <command>')
def run_command(command: str):
    cdp_eval(f"terminal.pty.write({command!r} + '\\n')")

@step('Вывод содержит <expected>')
def output_contains(expected: str):
    text = cdp_eval("xterm.buffer.active.getLine(...)")
    assert expected in text
```

**Запуск:** `gauge run tests/specs/mvp/` — прогон всех MVP-тестов.

### 7 тестов по DoD MVP

| Spec | DoD | Метод |
|------|-----|-------|
| `build-load.spec` | Плагин собирается и загружается | CDP: `app.plugins.plugins` |
| `open-terminal.spec` | Иконка + Command Palette | CDP: команда → DOM `.xterm` |
| `shell-exec.spec` | Команды выполняются | CDP: `pty.write` → `buffer.getLine` |
| `selection.spec` | Выделение мышью | CDP: `getSelection()` + скриншот |
| `scroll.spec` | Скролл | CDP: `viewport.scrollTop` + скриншот |
| `autofocus.spec` | Авто-фокус | CDP: `document.activeElement` |
| `close-no-zombie.spec` | Ctrl+D без зомби | CDP: закрытие → `ps aux \| grep` |

## Risks / unknowns

- **Gauge в контейнере.** Тесты требуют запущенный Obsidian с GUI — в `claudocker` это невозможно. Нужно либо гонять на хосте, либо скипать с `pytest.skip` в контейнере
- **Стабильность CDP.** Obsidian может менять внутренние идентификаторы команд, структуру DOM. Тесты нужно будет поддерживать при обновлении Obsidian
- **Визуальные проверки.** Скриншотные тесты недетерминированы (разное разрешение, тема, шрифты). Нужен baseline для конкретной машины (MacBook Air 2014)
- **Gauge vs чистый pytest.** Не переусложнит ли Gauge? Может, проще сразу pytest с `pytest-bdd` или даже без BDD-слоя? Gauge — ещё один инструмент в цепочке, который нужно установить и поддерживать
- **Зомби-тест.** Проверка через `ps aux` требует отдельного PTY или доступа к процессам хоста — в контейнере не сработает

## Notes

- Задача создана: [[2026-07-20--mvp-test-plan]]
- CDP-инфраструктура готова: `scripts/cdp-eval.py`, `scripts/cdp-screenshot.py`, `docs/cdp-testing.md`
- KB: [[cdp-remote-debugging]]
- Gauge: https://docs.gauge.org/
