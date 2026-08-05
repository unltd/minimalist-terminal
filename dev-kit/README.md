# Dev Kit

Developer tools for debugging and testing Minimalist Terminal.

## Structure

```
dev-kit/
├── README.md              # This file
├── debug/                 # Launch Obsidian with CDP + debugging
│   ├── debug.bat          # Windows: launch Obsidian + CDP, portproxy, firewall (batch, no PowerShell)
│   └── debug.py           # Python: unified CDP client (test, screenshot, eval, view)
├── cdp/                   # CDP scripts (Chrome DevTools Protocol)
│   ├── cdp-eval.py        # Execute JavaScript in Obsidian via CDP
│   └── cdp-screenshot.py  # Screenshot Obsidian via CDP (Page.captureScreenshot)
└── cdp-testing.md         # Documentation: how CDP testing works
```

## Quick Start

### 1. Launch Obsidian with CDP

**Windows:**
```cmd
dev-kit\debug\debug.bat C:\Users\tania\Documents\obsidian-test
```
The script finds Obsidian.exe on its own, launches it with `--remote-debugging-port`, and configures portproxy and firewall.

**macOS (manual):**
```bash
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*
```

### 2. Check the connection

```bash
CDP_HOST=192.168.1.144 python3 dev-kit/debug/debug.py test
# or locally:
python3 dev-kit/debug/debug.py test --local
```

### 3. Execute JS in Obsidian

```bash
python3 dev-kit/cdp/cdp-eval.py 'app.plugins.plugins["minimalist-terminal"]'
```

### 4. Take a screenshot

```bash
python3 dev-kit/cdp/cdp-screenshot.py              # auto name (N.png)
python3 dev-kit/cdp/cdp-screenshot.py my-test.png  # specific name
```

Screenshots are saved to `screenshots/` (gitignored, runtime-only).

## debug.py — universal client

```bash
python3 dev-kit/debug/debug.py test              # health check (TCP → CDP → JS eval)
python3 dev-kit/debug/debug.py view              # show all CDP targets
python3 dev-kit/debug/debug.py eval '<js>'       # execute JavaScript
python3 dev-kit/debug/debug.py screenshot        # screenshot (auto name)
python3 dev-kit/debug/debug.py screenshot x.png  # screenshot (specific name)
```

Arguments:
- `--local` — use 127.0.0.1 instead of `CDP_HOST`
- `CDP_HOST` (env) — IP of the remote machine (default 127.0.0.1)
- `CDP_PORT` (env) — port (default 9222)
- `CDP_VAULT` (env) — filter by vault name
- `CDP_TIMEOUT` (env) — timeout in seconds (default 15)

## cdp-eval.py — execute JS

```bash
python3 dev-kit/cdp/cdp-eval.py 'navigator.platform'

# Reload the plugin
python3 dev-kit/cdp/cdp-eval.py '
  app.plugins.disablePlugin("minimalist-terminal");
  await new Promise(r => setTimeout(r, 300));
  app.plugins.enablePlugin("minimalist-terminal");
'

# Open the terminal
python3 dev-kit/cdp/cdp-eval.py '
  let leaf = app.workspace.getLeaf("split", "horizontal");
  await leaf.setViewState({ type: "minimalist-terminal-view", active: true });
  app.workspace.revealLeaf(leaf);
'
```

The environment variables are the same: `CDP_HOST`, `CDP_PORT`, `CDP_VAULT`.

## cdp-screenshot.py — screenshot

```bash
python3 dev-kit/cdp/cdp-screenshot.py              # screenshots/N.png
python3 dev-kit/cdp/cdp-screenshot.py via-eval.png # screenshots/via-eval.png
```

## Related resources

- [CLAUDE.md](../CLAUDE.md) — plugin architecture, build, constraints
- [cdp-testing.md](./cdp-testing.md) — how CDP testing works
- [autodocs/knowledge-base/](../autodocs/knowledge-base/) — KB of non-obvious problems
- `.claude/skills/terminal-debug/` — Claude skill for CDP debugging
- `.claude/skills/screenshot-debug/` — Claude skill for visual diagnostics
