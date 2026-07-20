# nvm/node через shell: нужны флаги -l -i

**Дата:** 2026-07-18
**Статус:** resolved
**Связано:** [[electron-require-resolution]]

## Симптомы

Терминал открывается, bash работает, но команды из `.bashrc`/`.bash_profile` не видны:
```bash
$ which claude
claude not found
```

Хотя в обычном терминале macOS `which claude` показывает путь через nvm.

`$PATH` не содержит nvm-директорий.

## Причина

node-pty по умолчанию запускает shell **без флагов** — не login, не interactive. Без `-l` (login) `.bash_profile` не выполняется, nvm не инициализируется. Без `-i` (interactive) `.bashrc` не всегда читается.

На macOS `~/.bash_profile` обычно настраивает nvm:
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

## Решение

Запускать shell с флагами `-l -i`:

```typescript
const pty = spawn(shell, ["-l", "-i"], {
  name: "xterm-256color",
  cols, rows, cwd,
  env: process.env,
});
```

Также использовать `process.env.SHELL || "bash"` вместо принудительного `zsh` — пользователь может предпочитать другой shell.

## Ссылки

- [nvm README](https://github.com/nvm-sh/nvm#bash-shell-integration) — как nvm интегрируется с bash
- [node-pty spawn docs](https://github.com/microsoft/node-pty#usage) — аргументы spawn

## Как найти в коде

- `src/PtyBridge.ts` → `spawn(shell, ["-l", "-i"], ...)`
- `grep "SHELL\|spawn\|-l\|-i" src/PtyBridge.ts`
