# CDP Testing

Automated plugin testing via Chrome DevTools Protocol from a Docker container.

## How It Works

Obsidian runs on Electron (Chromium), which supports the [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/). Enable remote debugging with `--remote-debugging-port`, and from the container connect to Obsidian via WebSocket — execute JavaScript, take screenshots, analyze DOM.

```
┌─────────────────────────────────────────────────┐
│ macOS host                                       │
│  ┌──────────────────────────────────────────┐   │
│  │ Obsidian (Electron)                       │   │
│  │  CDP Server on 127.0.0.1:9222            │   │
│  └──────────────────────────────────────────┘   │
│                     ↑                            │
│                     │ host.docker.internal        │
│                     │ (192.168.65.254:9222)       │
├─────────────────────┼───────────────────────────┤
│ Docker container    │                            │
│  ┌──────────────────┴───────────────────────┐   │
│  │ dev-kit/cdp/cdp-eval.py                      │   │
│  │ dev-kit/cdp/cdp-screenshot.py                │   │
│  │  ↓                                       │   │
│  │  Raw WebSocket → CDP → JS execution      │   │
│  │  → DOM queries / screenshots             │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

## Starting Obsidian with Debugging

```bash
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*
```

- `--remote-debugging-port=9222` — CDP server port
- `--remote-allow-origins=*` — allows WebSocket connections from any origin (needed for Docker)
- Use `open -a` with `--args`, not a direct binary launch — otherwise Obsidian enters CLI mode

DevTools listens on `ws://127.0.0.1:9222` after launch.

## Tools

### `dev-kit/cdp/cdp-eval.py`

Executes JavaScript in Obsidian's context and returns the result.

```bash
python3 dev-kit/cdp/cdp-eval.py '<javascript expression>'
```

**Examples:**

```bash
# Connection check
python3 dev-kit/cdp/cdp-eval.py "'hello from obsidian!'"

# DOM diagnostics
python3 dev-kit/cdp/cdp-eval.py '
  JSON.stringify({
    screen: document.querySelector(".xterm-screen")?.className,
    selectionPos: getComputedStyle(document.querySelector(".xterm-selection")).position
  })
'

# Plugin actions
python3 dev-kit/cdp/cdp-eval.py '
  app.plugins.disablePlugin("minimalist-terminal");
  app.plugins.enablePlugin("minimalist-terminal");
  "reloaded"
'

# Open terminal
python3 dev-kit/cdp/cdp-eval.py '
  let leaf = app.workspace.getLeaf("split", "horizontal");
  leaf.setViewState({ type: "minimalist-terminal-view", active: true });
  "opened"
'

# Select text in terminal
python3 dev-kit/cdp/cdp-eval.py '
  let view = app.workspace.getLeavesOfType("minimalist-terminal-view")[0]?.view;
  view?.term?.selectLines(0, 3);
  "selected"
'
```

### `dev-kit/cdp/cdp-screenshot.py`

Takes a screenshot of the Obsidian window.

```bash
python3 dev-kit/cdp/cdp-screenshot.py            # auto-name (next number)
python3 dev-kit/cdp/cdp-screenshot.py test.png   # specific name
```

Screenshots are saved to `screenshots/`.

## How Scripts Work

Both scripts use **raw WebSocket** (not `websocket-client`) to bypass the Origin header check. CDP only accepts connections with `Origin: http://localhost:9222`, so the scripts:

1. HTTP GET `http://host.docker.internal:9222/json` (with `Host: localhost`)
2. Find the Obsidian page (`app://obsidian.md/index.html`)
3. Open a TCP socket, perform WebSocket handshake with the correct `Origin`
4. Send CDP commands (`Runtime.evaluate`, `Page.captureScreenshot`)
5. Parse the response

The container sees the host via `host.docker.internal` → `192.168.65.254`.

## Typical Debug Cycle

```
1. Change code
   ↓
2. npm run build              ← build
   ↓
3. cdp-eval.py '...reload...' ← reload plugin
   ↓
4. cdp-eval.py '...open...'   ← open terminal
   ↓
5. cdp-eval.py '...select...' ← select text
   ↓
6. cdp-screenshot.py          ← screenshot
   ↓
7. python3 -c "PIL analysis"   ← check pixels
```

Fully automated — no manual clicking, reloading, or selecting needed.

## Limitations

- **Origin check**: Electron by default only accepts WebSocket from `localhost`. Scripts bypass this with a raw socket and `Origin` header spoofing. If `--remote-allow-origins=*` works in your Electron version, there is no restriction.
- **Target ID changes** on each Obsidian restart. Scripts auto-fetch the current ID from `/json`.
- **Single Obsidian only**: scripts pick the first `app://obsidian.md` page; behavior is undefined with multiple windows open.
- **Screenshots via Page.captureScreenshot** — visible area only. Extensions needed for full-page screenshots.
