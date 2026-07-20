# Obsidian Terminal — Test Suite

Gauge + pytest тесты для плагина Obsidian Terminal. Спецификации на Markdown (`.spec`), имплементации шагов на Python/pytest.

## Структура

```
tests/
├── manifest.json              — Gauge project
├── env/default/
│   └── python.properties      — Python runner config
├── specs/                     — Gauge .spec файлы (Markdown)
│   └── mvp/                   — тесты для MVP Definition of Done
│       ├── build-load.spec
│       ├── open-terminal.spec
│       ├── shell-exec.spec
│       ├── selection.spec
│       ├── scroll.spec
│       ├── autofocus.spec
│       └── close-no-zombie.spec
├── step_impl/                 — pytest step implementations
│   ├── conftest.py            — общие фикстуры и CDP-клиент
│   └── test_*.py              — по одному файлу на .spec
└── README.md                  — этот файл
```

## Зависимости

```bash
# Gauge CLI
brew install gauge

# Gauge Python plugin
gauge install python

# Python dependencies
pip install getgauge pytest
```

## Запуск Obsidian с CDP

Тесты требуют запущенный Obsidian с удалённой отладкой:

```bash
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*
```

**Важно:** Obsidian должен быть запущен **до** тестов. Gauge-фикстуры подключаются к уже запущенному экземпляру.

### Из Docker-контейнера (claudocker)

CDP-скрипты по умолчанию подключаются к хосту через `192.168.65.254:9222`. Если Obsidian запущен на macOS хосте — всё должно работать автоматически.

### С macOS хоста

Установите переменную окружения, чтобы скрипты использовали localhost:

```bash
export CDP_HOST=127.0.0.1
```

## Запуск тестов

### Все MVP-тесты через Gauge

```bash
gauge run tests/specs/mvp/
```

### Конкретная спецификация

```bash
gauge run tests/specs/mvp/shell-exec.spec
```

### По тегам

```bash
gauge run --tags "doD-3" tests/specs/
gauge run --tags "cdp" tests/specs/
```

### Dry-run (валидация структуры, без выполнения)

```bash
gauge run --dry-run tests/specs/
```

### Через pytest напрямую (без Gauge)

```bash
pytest tests/step_impl/ -v
```

## Теги

Каждый `.spec`-файл размечен тегами:

| Тег | Значение |
|-----|----------|
| `mvp` | Тест для MVP |
| `doD-1` … `doD-7` | Какой пункт DoD проверяется |
| `cdp` | Автоматизирован через CDP |
| `visual` | Требует визуальной проверки (скриншот) |

## Как добавить новый тест

1. Создать `.spec`-файл в `tests/specs/<feature>/`
2. Описать сценарии в Gauge Markdown
3. Создать `test_*.py` в `tests/step_impl/` с `@step`-декораторами
4. Прогнать: `gauge run tests/specs/<feature>/`

Существующие шаги (из `conftest.py` и других `test_*.py`) переиспользуются автоматически — Gauge находит `@step` по тексту.

## Ограничения

- **Только локально.** Тесты требуют реальный Obsidian с GUI — CI невозможен без эмуляции дисплея
- **Один экземпляр Obsidian.** CDP-скрипты подключаются к первому окну `app://obsidian.md`
- **MacOS.** Команда `open -a Obsidian` — macOS-специфична
- **Нестабильность.** Obsidian может менять внутренние ID команд и структуру DOM — тесты нужно обновлять при мажорных версиях
