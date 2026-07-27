# Prepare-to-Prod Roadmap — obsidian-terminal

**Created:** 2026-07-27
**Status:** in-progress
**Estimate:** L (~50k)
**Branch:** main

## Overview / Goal

Подготовить obsidian-terminal к публичному использованию. Устранить блокеры, создать документацию, скрипты, CI — по чек-листу `/prepare-to-prod` (44 пункта).

Задача возникла по итогам dry-run `/prepare-to-prod --phase 1 --dry-run` (2026-07-24).

## Исходное состояние (обновлено 2026-07-27)

| Параметр | Было | Стало |
|----------|------|-------|
| Версия | 0.1.4 | 0.1.4 |
| Статус | private | private |
| README | ❌ | ✅ |
| Settings Tab | ❌ | ✅ (shell selection) |
| Shell по умолчанию | bash (hardcoded) | zsh (авто-детект) |
| CI | ❌ | ❌ |
| Лицензия | ❌ | ❌ |

## Критические блокеры (must fix before public) — ✅ Этап 1 завершён

| # | Статус | Проблема | Коммит |
|---|--------|----------|--------|
| B1 | ✅ | **Хардкод путей** в `findNodePty()` | `f9b3e8d` — pluginDir из vault basePath |
| B2 | ✅ | **`.env` с реальным токеном** | `f9b3e8d` — заменён на placeholder |
| B3 | ✅ | **README.md отсутствует** | `f9b3e8d`, `3a49650` — создан + обновлён |

## Высокий приоритет (should fix before public)

| # | Чек-лист | Проблема | Решение |
|---|----------|----------|---------|
| H1 | 1.13 | **CONTRIBUTING.md** отсутствует | Из `templates/CONTRIBUTING.md` |
| H2 | 1.14 | **CHANGELOG.md** отсутствует | Заготовка + `git log --oneline` |
| H3 | 1.15 | **Схема архитектуры** | Mermaid: main.ts → TerminalView → PtyBridge → node-pty |
| H4 | 1.17 | **`.env.example`** отсутствует | Извлечь `SHELL`, `HOME` из кода |
| H5 | 1.18-1.23 | **Скрипты + Makefile** отсутствуют | `scripts/build.sh`, `test.sh`, `lint.sh`, `Makefile` |
| H6 | 1.29 | **Платформенная матрица** | Подтвердить: macOS ✅ / Linux ✅(claudocker) / Windows ⚠️ |
| H7 | 1.35 | **Английский в `docs/`** | `cdp-testing.md`, `token-log.md`, `selection-fix-log.md` на русском — перевести или решить что это internal-only |
| H8 | 1.2 | **`.gitignore` неполный** | Добавить `.vscode/`, `.idea/`, `*.swp`, `*~`, `.pytest_cache/` |
| H9 | 1.3 | **`.gitattributes`** отсутствует | Создать с `* text=auto` |
| H10 | 1.6 | **`.DS_Store` в репо** | `git rm --cached .DS_Store` |

## Средний приоритет (nice to have)

| # | Чек-лист | Что | Решение |
|---|----------|-----|---------|
| M1 | 2.1 | **Лицензия** | Выбрать и добавить (MIT?) |
| M2 | 2.4 | **CI/CD** | GitHub Actions: lint → test → build |
| M3 | 2.6-2.7 | **Issue/PR templates** | Уже есть в `.github/`, актуализировать |
| M4 | 2.10 | **Первый публичный релиз** | v0.2.0 (с учётом B1) |
| M5 | 3.4 | **console.error** | `TerminalView.ts:261` — ок, это логгирование ошибки |
| M6 | — | **Linux без контейнера** | Протестировать сборку и запуск на голом Linux |
| M7 | — | **Windows тестирование** | ConPTY + Win 10 1809+. Нужен волонтёр или VM |

## Известные ограничения (не блокеры, но надо документировать)

| # | Ограничение | Где искать | Документировать в |
|---|-------------|-----------|-------------------|
| L1 | ~~**Ghost selection bug**~~ — исправлен (2026-07-24), см. `docs/archive/selection-fix-log.md` | — | — |
| L2 | **Борьба за фокус** — retry loop до 60 попыток | `TerminalView.ts:204-212` | README → Known Issues |
| L3 | **Нет синхронизации с темой Obsidian** | `TerminalView.ts:53-63` | README → Limitations |
| L4 | ~~Не настраивается~~ — Settings Tab с shell selection (2026-07-27) | — | — |
| L5 | ~~Только bash~~ — zsh default, авто-детект, выбор shell (2026-07-27) | — | — |
| L6 | **Только desktop** — мобильные не поддерживаются | `manifest.json:8` | README → Limitations |
| L7 | **macOS-специфичный node-pty форк** | `package.json` | README → Platform support |
| L8 | **Windows не тестировался** | — | README → Platform support |
| L9 | **MAX_TERMINALS = 10** | `TerminalView.ts:7` | Возможно, не стоит упоминать |
| L10 | **Хоткеи не настраиваются** | `TerminalView.ts:96-116` | README → Limitations |

## Implementation Plan

### Этап 1 — Критические блокеры ✅ (~12k факт, ~50k с shell-selection)

1. ✅ **B1: Убрать хардкод путей** — `f9b3e8d`
2. ✅ **B3: README.md** — `f9b3e8d`, `3a49650`
3. ✅ **B2: Токен в .env** — `f9b3e8d`
4. ✅ **Shell selection via Settings Tab** — `43c9990`, `e16761d`, `c6315b9` (закрывает L4, L5)
5. ✅ **User feedback loop** (идея) — `dc56bf0`

### Этап 2 — Высокий приоритет (~12k токенов)

4. H1-H5: CONTRIBUTING, CHANGELOG, архитектура, .env.example, скрипты + Makefile
5. H6: Платформенная матрица (ask пользователя)
6. H7-H10: Гигиена репозитория

### Этап 3 — Средний приоритет (~10k токенов)

7. M1: Лицензия
8. M2: CI/CD
9. M4: Релиз v0.2.0

## Definition of Done

- [x] B1: `findNodePty()` не содержит хардкод-путей, плагин работает после `git clone + npm ci + npm run build`
- [x] B3: README.md готов (описание, quickstart, ограничения, скриншоты)
- [x] B2: `.env` не содержит реального токена
- [x] L4: Settings Tab (shell selection) — `43c9990`
- [x] L5: Bash-only → zsh default с авто-детектом — `43c9990`
- [ ] H1-H5: CONTRIBUTING, CHANGELOG, архитектура, .env.example, скрипты созданы
- [ ] H6: Платформенная матрица подтверждена
- [ ] H8-H10: `.gitignore`, `.gitattributes`, `.DS_Store` исправлены
- [ ] M1: LICENSE добавлен
- [ ] M2: CI проходит (lint + test + build)
- [ ] Все 44 пункта `/prepare-to-prod --phase 1` пройдены
- [ ] Ограничения L1-L10 задокументированы в README

## Progress Log

| Дата | Что |
|------|-----|
| 2026-07-27 | Этап 1: B1, B2, B3 — критические блокеры устранены |
| 2026-07-27 | Shell selection: Settings Tab, zsh default, авто-детект, валидация |
| 2026-07-27 | README обновлён под shell selection |
| 2026-07-27 | Идея: user feedback loop (в плагин + Claude-триаж) |

## Notes

- Чек-лист: `/prepare-to-prod` (44 пункта)
- Идея: [[2026-07-20--pre-prod-to-prod-checklist]] (в obsidian-notes vault)
- Task в vault: [[2026-07-24--prepare-to-prod-skill]]
- Тесты уже есть (Gauge BDD) — это плюс
- Зависимости чисты (0 vulnerabilities) — ещё плюс
- Самое трудное позади: 15 попыток исправить ghost selection → проблема понята глубоко. Остальное — механика.
