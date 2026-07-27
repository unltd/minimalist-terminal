# Shell Selection via Settings Tab

**Created:** 2026-07-27
**Status:** ready
**Estimate:** M (~20k)
**Branch:** —
**Depends on:** [[2026-07-27--prepare-to-prod-roadmap]] (Этап 1 — B1 fix accepted)

## Overview / Goal

Заменить `process.env.SHELL || "bash"` на полноценный выбор shell через Settings Tab. Пользователь выбирает из обнаруженных в системе shell или указывает свой путь. Это первый шаг к полноценному Settings Tab (L4 в roadmap).

**Текущее состояние:**
```typescript
// PtyBridge.ts:40
const shell = process.env.SHELL || "bash";
// spawn с жёсткими флагами
const pty = spawn(shell, ["-l", "-i"], { ... });
```

**Проблемы:**
- Нельзя выбрать shell — только то, что в `$SHELL` у процесса Obsidian
- На macOS с bash 3.2 — предупреждение «The default interactive shell is now zsh» при каждом запуске
- Флаги `-l -i` захардкожены под bash — не подходят для fish, PowerShell, etc.
- Нет валидации — если shell не найден, ошибка только при spawn

## Design

### Plugin Settings (Data Schema)

```typescript
interface TerminalSettings {
  shell: string;  // Full path to shell executable, empty = auto-detect
}
```

### Settings Tab

Obsidian `PluginSettingTab` с двумя контролами:

1. **Dropdown** — список обнаруженных shell с путями:
   - `/bin/bash` — GNU Bash 3.2 (⚠️ outdated)
   - `/bin/zsh` — Zsh 5.x
   - `/bin/fish` — Fish (если найден)
   - `/usr/local/bin/bash` — GNU Bash 5.x (Homebrew)
   - ...
   - `Custom...` — текстовое поле

2. **Text input** (появляется при выборе Custom) — валидация:
   - Путь существует и является файлом
   - Файл исполняемый (`fs.access X_OK`)
   - При ошибке — красный border + сообщение

### Shell Detection

При открытии Settings Tab (и при загрузке плагина) сканируем известные локации:

```typescript
const KNOWN_SHELLS = [
  "/bin/bash",
  "/bin/zsh",
  "/bin/fish",
  "/bin/sh",
  "/usr/local/bin/bash",    // Homebrew bash (macOS)
  "/usr/local/bin/fish",    // Homebrew fish
  "/opt/homebrew/bin/bash", // Homebrew ARM
  "/opt/homebrew/bin/fish",
  "/usr/bin/fish",          // Linux fish
  "/usr/bin/zsh",           // Linux zsh
];
```

Сканируем `fs.existsSync` + `fs.accessSync(X_OK)`. Найденные — в dropdown. Плюс всегда опция Custom.

### Shell-Specific Flags

Разные shell требуют разных флагов для login+interactive режима:

| Shell | Flags |
|-------|-------|
| bash | `-l -i` (или `--login -i`) |
| zsh | `-l -i` (совместимо с bash) |
| fish | `-i` (login не нужен, флага `-l` нет) |
| sh/dash | `-i` (не все поддерживают `-l`) |

Детектить по basename или позволить пользователю указать флаги вручную (будущая фича, пока авто).

### Fallback-цепочка

1. Настройка пользователя (если задана и валидна)
2. `process.env.SHELL` (если существует и исполняемый)
3. Первый найденный из `KNOWN_SHELLS`
4. `"bash"` (пусть упадёт с понятной ошибкой)

## Implementation Plan

### 1. Settings data model (`src/settings.ts` — новый файл)

- `DEFAULT_SETTINGS: TerminalSettings`
- `KNOWN_SHELLS` — массив путей для сканирования
- `detectShells()` — возвращает доступные shell
- `resolveShell(userSetting: string): { path: string, flags: string[] }`

### 2. Settings Tab (`src/SettingsTab.ts` — новый файл)

- `PluginSettingTab` subclass
- Dropdown с обнаруженными shell + Custom option
- Text input с live-валидацией
- Сохранение в `plugin.settings`

### 3. Plugin integration (`src/main.ts`)

- `loadSettings()` / `saveSettings()` в `TerminalPlugin`
- `settings` поле в Plugin
- Регистрация `SettingsTab`

### 4. PtyBridge adaptation (`src/PtyBridge.ts`)

- Принимать `shell` как параметр конструктора (вместо чтения `process.env.SHELL`)
- Shell-specific flags (определять по basename)
- Fallback если shell не найден → сообщение в терминал

### 5. TerminalView passthrough (`src/TerminalView.ts`)

- Пробросить shell из настроек плагина в `new PtyBridge(...)`

## Completed

- [ ] Ничего

## Remaining

- [ ] Settings data model
- [ ] Shell detection
- [ ] Settings Tab UI
- [ ] Plugin integration
- [ ] PtyBridge adaptation
- [ ] Тестирование: авто-детект + ручной выбор + custom path + fallback

## Definition of Done

- [ ] Settings Tab доступен: Settings → Community Plugins → Terminal → Options
- [ ] Dropdown показывает все обнаруженные shell + Custom option
- [ ] При выборе Custom — текстовое поле с валидацией (существует, исполняемый)
- [ ] Терминал открывается с выбранным shell
- [ ] Если shell не найден — сообщение об ошибке в терминале, а не краш плагина
- [ ] Флаги shell-specific: bash/zsh → `-l -i`, fish → `-i`, sh → `-i`
- [ ] Предупреждение `The default interactive shell is now zsh` больше не появляется при старте терминала
- [ ] Билд проходит без ошибок

## Open Questions

1. **Scope Settings Tab:** ✅ Minimal — только shell, но структура готова для будущих настроек.
2. **Detection timing:** ✅ При загрузке плагина + рескан при открытии Tab.
3. **Fallback при spawn:** ✅ Показать ошибку в терминале + предложить зайти в настройки и выбрать другой shell.
4. **macOS bash 3.2:** ✅ Показывать ⚠️ предупреждение в UI.
5. **Сразу или после Этапа 2:** ✅ Делать сейчас.

### DoD (уточнения пользователя)

- [ ] Минимум bash и zsh в списке выбора
- [ ] По умолчанию предлагается zsh (если найден) — он современнее
- [ ] Пользователь может выбрать zsh и работать с ним
- [ ] При недоступности shell — ошибка в терминале + путь в настройки

## Notes

- L4 в roadmap: «Не настраивается — нет Settings Tab» → эта задача закрывает его
- L5 в roadmap: «Только bash по умолчанию» → закрывает
- macOS warning про zsh → уходит, потому что пользователь сможет явно выбрать zsh или brew bash
