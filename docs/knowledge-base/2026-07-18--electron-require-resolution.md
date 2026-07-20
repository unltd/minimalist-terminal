# Electron renderer: node-pty требует абсолютный путь в require()

**Дата:** 2026-07-18
**Статус:** resolved
**Связано:** [[esbuild-native-modules-external]]

## Симптомы

При загрузке плагина ошибка:
```
Error: Cannot find module '@lydell/node-pty'
```

Или плагин запускается, но терминал показывает красное сообщение "node-pty not found".

Хотя `@lydell/node-pty` установлен в `node_modules/` плагина и `require()` из DevTools Console работает.

## Причина

Electron-рендерер (в котором работает Obsidian) разрешает `require()` **относительно `Obsidian.app/Contents/Resources/app.asar`**, а не относительно директории плагина.

`node_modules/@lydell/node-pty` лежит в директории проекта/плагина, но Electron ищет модули внутри своего `.asar`-архива (`app.asar`) и не находит node-pty.

## Решение

Использовать **абсолютный путь** в `require()`. Сканировать известные локации через `fs.existsSync`:

```typescript
private static findNodePty(): string {
  const candidates = [
    "/Users/pavel/IdeaProjects/obsidian-terminal/node_modules/@lydell/node-pty",
    "/Users/pavel/obsidian-notes/.obsidian/plugins/obsidian-terminal/node_modules/@lydell/node-pty",
    path.join(process.cwd(), "node_modules/@lydell/node-pty"),
  ];
  for (const p of candidates) {
    if (fs.existsSync(path.join(p, "index.js"))) return p;
  }
  return "@lydell/node-pty"; // fallback
}
```

`install.sh` устанавливает `@lydell/node-pty` в обе локации (проект + vault plugin dir).

## Ссылки

- [Electron #12924](https://github.com/electron/electron/issues/12924) — `require()` resolution in renderer
- [`@lydell/node-pty`](https://www.npmjs.com/package/@lydell/node-pty) — fork с лучшим покрытием prebuild-билдов

## Как найти в коде

- `src/PtyBridge.ts` → `findNodePty()`
- `esbuild.config.mjs` → поле `external`: `"@lydell/node-pty"`
