# Нативные Node.js модули должны быть external в esbuild

**Дата:** 2026-07-18
**Статус:** resolved
**Связано:** [[electron-require-resolution]]

## Симптомы

При попытке загрузить плагин Obsidian показывает:
```
Failed to load plugin obsidian-terminal
```

Или при вызове `require('@lydell/node-pty')`:
```
Error: Cannot find module './build/Release/pty.node'
```

## Причина

esbuild **не умеет бандлить нативные Node.js модули** (`.node` файлы). При попытке сборки они либо исключаются (пустой модуль), либо пути к ним ломаются.

`@lydell/node-pty` содержит нативный аддон (`pty.node`), загружаемый через `bindings` или прямой `require()`. Этот файл должен остаться на диске и загружаться Node.js runtime.

Также Obsidian (как Electron-приложение) имеет встроенные Node.js модули (fs, path), которые тоже нельзя бандлить.

## Решение

Все нативные и встроенные модули должны быть перечислены в `external` конфигурации esbuild:

```javascript
// esbuild.config.mjs
const context = await esbuild.context({
  external: [
    "obsidian",     // Obsidian API (предоставляется хостом)
    "electron",      // Electron API
    "@lydell/node-pty",  // нативный аддон
    ...builtins,     // все встроенные Node.js модули (fs, path, etc.)
  ],
  format: "cjs",
  // ...
});
```

Для стабильной работы на macOS нужен пакет `@lydell/node-pty-darwin-arm64` (или x64 для Intel). `install.sh` автоматически определяет архитектуру и устанавливает нужный.

## Ссылки

- [esbuild docs: external](https://esbuild.github.io/api/#external) — как работает external
- [`@lydell/node-pty`](https://www.npmjs.com/package/@lydell/node-pty) — форк node-pty с лучшими prebuild

## Как найти в коде

- `esbuild.config.mjs` → массив `external`
- `package.json` → `dependencies`: `@lydell/node-pty`, `@lydell/node-pty-darwin-x64`
- `install.sh` → секция установки node-pty
