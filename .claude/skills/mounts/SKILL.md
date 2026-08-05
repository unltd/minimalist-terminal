---
name: mounts
description: Show mounted directories configured for claudocker
user-invocable: true
allowed-tools:
  - Read
  - Bash(cat *)
  - Bash(python3 *)
  - Bash(echo *)
---

# /mounts — Mounted directories

Show the list of mounted directories configured in `.claudocker/settings.json`.

## Steps

1. Read `.claudocker/settings.json` (if present) and show the contents of the `mounts` key.

2. If the file is missing — report that the project is not configured for claudocker, and suggest running `claudocker` to initialize.

3. For each additional directory in `mounts`, check whether it exists on disk and mark its status.

4. Also show the standard mounts that claudocker adds automatically:
   - `$PWD` → `$PWD` (current project)
   - `~/.claude` → `/home/dev/.claude` (Claude history)
   - `~/.claude.json` → `/home/dev/.claude.json` (auth config)

5. If Docker is configured (mode `dind`, `dood` or `auto`), also show the corresponding mounts.

6. If `mounts` is empty — suggest adding directories via `claudocker --add-mount <path>` or by editing `.claudocker/settings.json`.

## Example output

```
📁 Additional mounted directories (2):
  1. /home/user/other-project  (✓ exists)
  2. /mnt/shared-libs           (⚠️  not found)

📌 Standard mounts:
  • project         → /home/user/my-project
  • claude config   → ~/.claude → /home/dev/.claude
  • claude auth     → ~/.claude.json → /home/dev/.claude.json
  • docker (DinD)   → its own daemon (privileged)

💡 To add a directory: claudocker --add-mount /path/to/folder
```
