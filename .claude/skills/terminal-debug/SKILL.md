---
name: terminal-debug
description: Debug Minimalist Terminal via CDP — automated tests, screenshots, pixel analysis without manual actions
user-invocable: true
---

# terminal-debug

Automated plugin debugging via Chrome DevTools Protocol. The scripts `dev-kit/cdp/cdp-eval.py` and `dev-kit/cdp/cdp-screenshot.py` let you execute JS in Obsidian and take screenshots from the container.

## Launching Obsidian with CDP

**macOS:**
```bash
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*
```

**Windows:**
```cmd
debug.bat "C:\Users\tania\Documents\obsidian-test"
```
Or manually:
```cmd
"C:\Users\tania\AppData\Local\Obsidian\Obsidian.exe" --remote-debugging-port=9222 "C:\Users\tania\Documents\obsidian-test"
```
Important: `--remote-debugging-address=0.0.0.0` is not needed for local testing. The `--remote-allow-origins=*` flag is also optional.

## Tools

### cdp-eval.py — execute JS

```bash
python3 dev-kit/cdp/cdp-eval.py '<expression>'
```

### cdp-screenshot.py — screenshot

```bash
python3 dev-kit/cdp/cdp-screenshot.py          # screenshots/N.png
python3 dev-kit/cdp/cdp-screenshot.py name.png # screenshots/name.png
```

## Frequently used commands

### Reload the plugin
```bash
python3 dev-kit/cdp/cdp-eval.py '
  app.plugins.disablePlugin("minimalist-terminal");
  await new Promise(r => setTimeout(r, 300));
  app.plugins.enablePlugin("minimalist-terminal");
'
```

### Open the terminal
```bash
python3 dev-kit/cdp/cdp-eval.py '
  let leaf = app.workspace.getLeaf("split", "horizontal");
  await leaf.setViewState({ type: "minimalist-terminal-view", active: true });
  app.workspace.revealLeaf(leaf);
'
```

### Accessing TerminalView and xterm
```js
let view = app.workspace.getLeavesOfType("minimalist-terminal-view")[0]?.view;
// view.term   — xterm.js Terminal
// view.pty    — PtyBridge
// view.container — container HTMLElement
```

### Selecting text via xterm API
```js
view.term.selectLines(0, 3);           // lines 0-2
view.term.selectAll();                 // entire buffer
view.term.getSelection();              // selection text
view.term.clearSelection();
```

### DOM diagnostics of selection
```js
let sel = document.querySelector(".xterm-selection");
let rows = document.querySelector(".xterm-rows");
JSON.stringify({
  selPos: getComputedStyle(sel).position,
  screenPos: getComputedStyle(document.querySelector(".xterm-screen")).position,
  diff: Math.round(sel.getBoundingClientRect().top - rows.getBoundingClientRect().top),
  selChildren: sel.childNodes.length,
  selectionDivStyles: Array.from(sel.childNodes).map(c => c.style.cssText)
});
```

### Pixel analysis of the screenshot
```python
from PIL import Image
img = Image.open('screenshots/N.png')
# terminal: #1e1e1e ≈ (30,30,30)
# selection: #264f78 ≈ (38,79,120)
# text:     #d4d4d4 ≈ (212,212,212)
```

## Problems and their symptoms

| Symptom | Likely cause | What to check |
|---------|------------------|---------------|
| Selection ghost (two blue rectangles) | `.xterm-screen` lost `position: relative` | `getComputedStyle(screen).position` |
| `$$$$` over the text | `.xterm-char-measure-element` lost `visibility: hidden` | `getComputedStyle(measure).visibility` |
| Selection does not match text | `diff !== 0` between `.xterm-selection` and `.xterm-rows` | `getBoundingClientRect()` of both layers |
| Text not visible through selection | `background-color` solid, not rgba | `getComputedStyle(selDiv).backgroundColor` |

## Obsidian CSS overrides

Obsidian globally resets `position` to `static` on many elements. The xterm.js v5 DOM renderer requires:

- `.xterm-screen` — `position: relative` (containing block for selection)
- `.xterm-helpers` — `position: absolute; top: 0` (not taking up flow)
- `.xterm-char-measure-element` — `position: absolute; left: -9999em; visibility: hidden` (invisible)
- `.xterm-helper-textarea` — `position: absolute; opacity: 0; left: -9999em` (hidden)

All the guards are in `styles.css` via `!important`.

## Testing Copy/Paste

### Verifying paste is not duplicated

**Correct approach** — synthetic DOM events (NOT `Input.dispatchKeyEvent`):

```js
// 1. Spy on pty.write (not readText — it causes a loop!)
var v = app.workspace.getLeavesOfType("minimalist-terminal-view")[0]?.view;
var ow = v.pty.write.bind(v.pty);
var wc = 0;
v.pty.write = function(d) { wc++; return ow(d); };

// 2. Emulate Ctrl+V via keydown + paste events
var ta = v.term.element.querySelector("textarea");
ta.dispatchEvent(new KeyboardEvent("keydown", {
    key: "v", code: "KeyV", ctrlKey: true, shiftKey: false,
    bubbles: true, cancelable: true
}));
ta.dispatchEvent(new ClipboardEvent("paste", {
    bubbles: true, cancelable: true,
    clipboardData: new DataTransfer()
}));

// 3. Check: wc should be 0 (our handler does not call readText)
//    or 1 (if the paste guard writes synchronously)
JSON.stringify({writeCount: wc});
```

### Verifying the paste guard blocks xterm.js

```js
var pasteFired = false;
ta.addEventListener("paste", function(e) { pasteFired = true; });
ta.dispatchEvent(new ClipboardEvent("paste", {
    bubbles: true, cancelable: true,
    clipboardData: new DataTransfer()
}));
// pasteFired should be false (guard stopImmediatePropagation)
```

### Verifying Ctrl+C without selection = SIGINT

```js
var ow = navigator.clipboard.writeText.bind(navigator.clipboard);
var wc = 0;
navigator.clipboard.writeText = function(d) { wc++; return ow(d); };
ta.dispatchEvent(new KeyboardEvent("keydown", {
    key: "c", code: "KeyC", ctrlKey: true, shiftKey: false,
    bubbles: true, cancelable: true
}));
navigator.clipboard.writeText = ow;
// wc should be 0 (not copy, but SIGINT)
```

## Managing CDP connections

**Critical:** every WebSocket connection must be closed. Otherwise they accumulate and block new ones.

### Pattern: one connection per command series

```python
from debug import http_get, find_obsidian_page, ws_connect, ws_send, ws_recv
import json

page = find_obsidian_page(http_get('/json'), None)
sock = ws_connect(page, 15)

# All commands through one socket
for cmd in commands:
    ws_send(sock, cmd)
    result = ws_recv(sock)

sock.close()  # ← MANDATORY
```

### Rules

1. **One connection** for the entire test series
2. **Always `sock.close()`** at the end
3. **Do not create >5 connections** per session
4. **After tests — restart Obsidian** to clean up
5. **Do not use `debug.py eval` in a loop** — each call creates a new connection

### What does NOT work

- `Input.dispatchKeyEvent` for testing paste (gives a false double paste)
- Stubbing `navigator.clipboard.readText` (causes a recursive loop)
- `location.reload()` for reloading the plugin (Obsidian caches)
- `Page.captureScreenshot` without `Page.enable`
