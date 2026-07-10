---
name: mounts
description: Показать смонтированные директории, настроенные для claudocker
user-invocable: true
allowed-tools:
  - Read
  - Bash(cat *)
  - Bash(python3 *)
  - Bash(echo *)
---

# /mounts — Монтируемые директории

Показать список смонтированных директорий, настроенных в `.claudocker/settings.json`.

## Steps

1. Прочитай `.claudocker/settings.json` (если есть) и покажи содержимое ключа `mounts`.

2. Если файла нет — сообщи, что проект не настроен для claudocker, и предложи запустить `claudocker` для инициализации.

3. Для каждой дополнительной директории в `mounts` проверь, существует ли она на диске, и отметь статус.

4. Также покажи стандартные монтирования, которые claudocker добавляет автоматически:
   - `$PWD` → `$PWD` (текущий проект)
   - `~/.claude` → `/home/dev/.claude` (история Claude)
   - `~/.claude.json` → `/home/dev/.claude.json` (конфиг аутентификации)

5. Если Docker настроен (режим `dind`, `dood` или `auto`), тоже покажи соответствующие монтирования.

6. Если `mounts` пуст — предложи добавить директории через `claudocker --add-mount <путь>` или отредактировав `.claudocker/settings.json`.

## Пример вывода

```
📁 Дополнительные монтируемые директории (2):
  1. /home/user/other-project  (✓ существует)
  2. /mnt/shared-libs           (⚠️  не найдена)

📌 Стандартные монтирования:
  • проект          → /home/user/my-project
  • claude config   → ~/.claude → /home/dev/.claude
  • claude auth     → ~/.claude.json → /home/dev/.claude.json
  • docker (DinD)   → свой демон (privileged)

💡 Для добавления директории: claudocker --add-mount /путь/к/папке
```
