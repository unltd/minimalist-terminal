# MVP Test Plan — Gauge + pytest

**Created:** 2026-07-20
**Status:** done
**Estimate:** M (~20k)
**Branch:** main
**Depends on:** [[2026-07-10--obsidian-terminal-mvp]]

## Overview / Goal

Создать план тестирования в папке `tests/`, покрывающий пункты Definition of Done из задачи [[2026-07-10--obsidian-terminal-mvp|MVP]].

**Спецификации тестов** — Gauge в формате Markdown (`.spec`-файлы). **Имплементация шагов** — pytest с использованием библиотеки `getgauge`. Тесты взаимодействуют с Obsidian через CDP (`scripts/cdp-eval.py` / `scripts/cdp-screenshot.py`).

## Why

- Сейчас тестирование ad-hoc: ручной запуск `cdp-eval.py` с JS-сниппетами. Нет структуры, нельзя прогнать регресс одной командой
- Gauge даёт человекочитаемые спецификации на Markdown — порог входа ниже, чем у pytest-bdd или behave
- pytest — стандарт в Python-экосистеме, фикстуры идеально ложатся на управление Obsidian через CDP
- Каждый пункт DoD превращается в воспроизводимый формальный тест, а не в ручную проверку «на глаз»

## Design

### Почему Gauge + pytest

- **Gauge** даёт человекочитаемые спецификации на Markdown с BDD-синтаксисом (`## Scenario`, `* step`), понятные не-разработчику
- **pytest** — стандартный Python-раннер с мощными фикстурами, параметризацией и плагинами
- **Связка:** Gauge-спеки описывают *что* тестируем, pytest-степы — *как* (через CDP)
- CDP-инфраструктура уже существует (`scripts/cdp-eval.py`, `cdp-screenshot.py`), остаётся обернуть в pytest-фикстуры

### Структура `tests/`

```
tests/
├── manifest.json              — Gauge project manifest (language: python)
├── env/
│   └── default/
│       └── python.properties  — Gauge runner config
├── specs/                     — Gauge .spec файлы (Markdown)
│   └── mvp/
│       ├── build-load.spec    — сборка и загрузка плагина
│       ├── open-terminal.spec — открытие по иконке и Command Palette
│       ├── shell-exec.spec    — выполнение команд, вывод
│       ├── selection.spec     — выделение текста мышью
│       ├── scroll.spec        — скролл
│       ├── autofocus.spec     — авто-фокус при открытии
│       └── close-no-zombie.spec — закрытие по Ctrl+D, нет зомби
├── step_impl/                 — pytest step implementations
│   ├── __init__.py
│   ├── conftest.py            — фикстуры: CDP-соединение, запуск Obsidian
│   ├── test_build_load.py
│   ├── test_open_terminal.py
│   ├── test_shell_exec.py
│   ├── test_selection.py
│   ├── test_scroll.py
│   ├── test_autofocus.py
│   └── test_close_no_zombie.py
└── README.md                  — как запускать, зависимости, структура
```

### Gauge Spec → pytest Step: пример

**Файл спецификации** `specs/mvp/shell-exec.spec`:

```gauge
# Shell Execution

Проверка выполнения команд в терминале.

## Выполнение команды и вывод
Tags: mvp, doD-3, cdp

* Открыть терминал
* Дождаться приглашения командной строки длительностью до 5 секунд
* Выполнить команду "echo hello"
* Вывод содержит "hello"
```

**Файл имплементации** `step_impl/test_shell_exec.py`:

```python
import pytest
from getgauge.python import step
import subprocess

@step("Открыть терминал")
def open_terminal():
    """Клик по иконке терминала через CDP."""
    subprocess.run(
        ["python3", "scripts/cdp-eval.py",
         "app.commands.executeCommandById('obsidian-terminal:open-terminal')"],
        check=True
    )

@step("Дождаться приглашения командной строки длительностью до <seconds> секунд")
def wait_for_prompt(seconds: str):
    ...

@step('Выполнить команду <command>')
def run_command(command: str):
    ...

@step('Вывод содержит <expected>')
def output_contains(expected: str):
    ...
```

### conftest.py: общие фикстуры

```python
# step_impl/conftest.py
import pytest
import subprocess
import time

@pytest.fixture(scope="module")
def obsidian_process():
    """Запуск Obsidian с CDP-портом, убиваем после тестов."""
    proc = subprocess.Popen([
        "open", "-a", "Obsidian", "--args",
        "--remote-debugging-port=9222",
        "--remote-allow-origins=*"
    ])
    time.sleep(3)  # дать Obsidian загрузиться
    yield proc
    proc.terminate()
    proc.wait()

@pytest.fixture
def cdp(obsidian_process):
    """Возвращает хелпер для CDP-вызовов."""
    return CdpClient()
```

### Подход к автоматизации

| DoD | Gauge Spec | Тип проверки | CDP-метод |
|-----|-----------|-------------|-----------|
| Сборка и загрузка | `build-load.spec` | Проверка наличия плагина в `app.plugins.plugins` | `cdp-eval.py` |
| Открытие по иконке и CP | `open-terminal.spec` | Вызов команды, проверка DOM-элемента `.xterm` | `cdp-eval.py` |
| Выполнение команд | `shell-exec.spec` | `pty.write()` → `xterm.buffer.getLine()` | `cdp-eval.py` |
| Выделение мышью | `selection.spec` | Проверка `xterm.getSelection()` + скриншот | `cdp-eval.py` + `cdp-screenshot.py` |
| Скролл | `scroll.spec` | Проверка `viewport.scrollTop` + скриншот | `cdp-eval.py` + `cdp-screenshot.py` |
| Авто-фокус | `autofocus.spec` | `document.activeElement` === xterm textarea | `cdp-eval.py` |
| Ctrl+D без зомби | `close-no-zombie.spec` | `ps aux | grep node-pty` после закрытия | `cdp-eval.py` + shell |

## Implementation plan

### 1. Инициализация Gauge-проекта

- Установить `gauge` CLI и `gauge-python` плагин
- Создать `tests/manifest.json` с `language: python`
- Создать `tests/env/default/python.properties`
- Добавить зависимости в `requirements-dev.txt` или `pyproject.toml`

### 2. Базовая инфраструктура

- `tests/step_impl/conftest.py` — фикстуры для CDP и управления Obsidian
- `tests/step_impl/__init__.py`
- `tests/README.md` — инструкции по запуску и написанию новых тестов

### 3. Написать Gauge-спецификации (7 `.spec`-файлов)

Для каждого пункта DoD MVP — один `.spec`-файл со сценариями.

### 4. Реализовать pytest-степы (7 файлов)

Каждый файл реализует шаги для соответствующего `.spec`-файла.

### 5. Проверить прогон

```bash
gauge run tests/specs/mvp/
```

## Definition of Done

- [ ] `tests/manifest.json` — Gauge-проект инициализирован
- [ ] `tests/env/default/python.properties` — настроен python-раннер
- [ ] `tests/step_impl/conftest.py` — фикстуры CDP + Obsidian
- [ ] `tests/specs/mvp/` — 7 `.spec`-файлов по пунктам DoD MVP
- [ ] `tests/step_impl/` — 7 `test_*.py` файлов с имплементациями шагов
- [ ] Каждый `.spec` содержит минимум один `## Scenario` с тэгами `mvp, doD-N`
- [ ] Все шаги реализованы через вызовы `scripts/cdp-eval.py` или `scripts/cdp-screenshot.py`
- [ ] `tests/README.md` описывает установку, запуск (`gauge run`, `pytest`), и добавление новых тестов
- [ ] `gauge run tests/specs/mvp/` завершается без ошибок (тесты могут фейлиться если Obsidian не запущен, но структура валидна)
- [ ] Файл задачи [[2026-07-10--obsidian-terminal-mvp|MVP]] обновлён: DoD-пункты залинкованы на соответствующие `.spec`-файлы

## Risks

- **Gauge в контейнере.** Тесты требуют запущенный Obsidian с GUI — в `claudocker` это невозможно. Нужно либо гонять на хосте, либо скипать с `pytest.skip` в контейнере
- **Стабильность CDP.** Obsidian может менять внутренние идентификаторы команд, структуру DOM. Тесты нужно будет поддерживать при обновлении Obsidian
- **Визуальные проверки.** Скриншотные тесты недетерминированы (разное разрешение, тема, шрифты). Нужен baseline для конкретной машины (MacBook Air 2014)
- **Gauge vs чистый pytest.** Не переусложнит ли Gauge? Может, проще сразу pytest с `pytest-bdd` или даже без BDD-слоя? Gauge — ещё один инструмент в цепочке, который нужно установить и поддерживать
- **Зомби-тест.** Проверка через `ps aux` требует отдельного PTY или доступа к процессам хоста — в контейнере не сработает

## Open questions

- [ ] Нужен ли `pytest` как fallback-раннер независимо от Gauge (т.е. чтобы `pytest tests/step_impl/` тоже работал)?
- [ ] Хранить ли baseline-скриншоты в репозитории для visual diff?
- [ ] Добавить ли CI (GitHub Actions) с headless Obsidian или ограничиться локальным запуском?

## Testing

```bash
# Установка Gauge (один раз)
brew install gauge
gauge install python

# Запуск всех MVP-тестов
gauge run tests/specs/mvp/

# Запуск конкретной спецификации
gauge run tests/specs/mvp/shell-exec.spec

# Запуск по тегам
gauge run --tags "doD-3" tests/specs/

# Dry-run (только парсинг, без выполнения)
gauge run --dry-run tests/specs/

# Запуск step-имплементаций через pytest (если настроен)
pytest tests/step_impl/ -v
```

## Notes

- **Gauge** и **pytest** — два независимых раннера; связка работает через `getgauge.python.step`-декораторы
- CDP-тестирование требует запущенного Obsidian с `--remote-debugging-port=9222` — фикстура `conftest.py` управляет этим
- При прогоне в контейнере (`claudocker`) Obsidian недоступен — тесты будут скипаться с `pytest.skip` или требовать отдельного хоста
- См. `docs/cdp-testing.md` для деталей CDP-инфраструктуры
- Связанные KB: [[cdp-remote-debugging]]
- Gauge docs: https://docs.gauge.org/
