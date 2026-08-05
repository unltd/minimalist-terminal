---
name: screenshot-debug
description: Screenshot debugging — capture, pixel analysis, diagnosis of terminal rendering issues
user-invocable: true
---

# screenshot-debug

Specialized skill for the "screenshot → pixel analysis → diagnosis" loop. Unlike `terminal-debug` (general debugging), this skill focuses on visual diagnostics: capturing a screenshot via CDP, extracting pixel data, correlating with the DOM state, forming hypotheses.

## When to use

- After changing CSS/DOM structure — check that selection did not break
- For any visual bug: selection ghosts, text offset, `$$$$` in the corner
- Before committing — quick visual diff
- When the user sends a screenshot — analyze and give a conclusion

## Tools

### Capture

```bash
python3 dev-kit/cdp/cdp-screenshot.py              # screenshots/N.png (auto-increment)
python3 dev-kit/cdp/cdp-screenshot.py name.png     # screenshots/name.png
python3 dev-kit/cdp/cdp-screenshot.py via-eval.png # screenshot + extra JS before capture
```

### Pixel analysis (PIL)

```python
from PIL import Image
import numpy as np

img = Image.open('screenshots/N.png')
arr = np.array(img)

# Brightness profile by columns (find blue selection blocks)
blue_mask = (arr[:,:,2] > 100) & (arr[:,:,0] < 80) & (arr[:,:,1] < 100)
blue_rows = blue_mask.any(axis=1)  # True where blue exists

# Text brightness profile by rows
gray = np.mean(arr, axis=2)
luminance = gray.mean(axis=1)  # mean brightness of each row

# Find text rows: dark background (~30) + light text (~212) = luminance ~40-60
text_rows = (luminance > 35) & (luminance < 80)
```

### Diagnostic JS snippets

```js
// Check position of key elements
(() => {
  const els = {
    screen: document.querySelector('.xterm-screen'),
    selection: document.querySelector('.xterm-selection'),
    rows: document.querySelector('.xterm-rows'),
    helpers: document.querySelector('.xterm-helpers'),
    measure: document.querySelector('.xterm-char-measure-element'),
    textarea: document.querySelector('.xterm-helper-textarea'),
  };
  const result = {};
  for (const [name, el] of Object.entries(els)) {
    if (!el) { result[name] = null; continue; }
    const cs = getComputedStyle(el);
    result[name] = {
      position: cs.position,
      display: cs.display,
      visibility: cs.visibility,
      rect: el.getBoundingClientRect(),
    };
  }
  return JSON.stringify(result, null, 2);
})();
```

```js
// Check the offset between the selection and rows layers
(() => {
  const sel = document.querySelector('.xterm-selection');
  const rows = document.querySelector('.xterm-rows');
  if (!sel || !rows) return 'missing elements';
  const sr = sel.getBoundingClientRect();
  const rr = rows.getBoundingClientRect();
  return JSON.stringify({
    selection: { top: sr.top, left: sr.left, width: sr.width, height: sr.height },
    rows: { top: rr.top, left: rr.left, width: rr.width, height: rr.height },
    diffY: Math.round(sr.top - rr.top),
    diffX: Math.round(sr.left - rr.left),
  });
})();
```

## Diagnostic patterns

### Selection ghost (two blue blocks instead of one)

**Symptom:** on the screenshot there are two blue rectangles — one in place, the second offset.
**Pixel signature:** two disjoint groups of blue pixels with different Y coordinates.
**Cause:** `.xterm-screen` lost `position: relative` → the selection layer is positioned from body, not from screen.
**Check:** `getComputedStyle(screen).position` — should be `relative`.
**Fix:** `styles.css` → `.xterm-screen { position: relative !important; }`

### Selection does not match text (Y offset)

**Symptom:** the blue block is above or below the text it should cover.
**Pixel signature:** `diffY !== 0` between the blue pixel zone and the text pixel zone.
**Cause:** selection top and rows top diverge (usually because helpers take up space in the flow).
**Check:** the "offset between layers" snippet above.
**Fix:** `.xterm-helpers { position: absolute; top: 0; } !important`

### $$$$ in the corner of the screen

**Symptom:** four dollar signs in the top-left corner of the terminal.
**Pixel signature:** light pixels in the (0,0)-(40,20) zone with no text there.
**Cause:** `.xterm-char-measure-element` lost `visibility: hidden`.
**Check:** `getComputedStyle(measure).visibility` — should be `hidden`.
**Fix:** `.xterm-char-measure-element { visibility: hidden !important; }`

### Solid fill (text not visible through selection)

**Symptom:** the blue rectangle is opaque, text underneath is unreadable.
**Pixel signature:** no light text pixels inside the blue zone.
**Cause:** `background-color` is solid (e.g. `#264f78`), not semi-transparent.
**Check:** `getComputedStyle(selDiv).backgroundColor` — should be `rgba(38, 79, 120, 0.3)` or similar.
**Fix:** override background-color of `.xterm-selection div` to rgba with transparency.

## Debug loop

```
1. Build:       npm run build
2. Reload:      python3 dev-kit/cdp/cdp-eval.py '...reload plugin...'
3. Setup:       python3 dev-kit/cdp/cdp-eval.py '...open terminal + select...'
4. Screenshot:  python3 dev-kit/cdp/cdp-screenshot.py
5. Read:        Read screenshots/N.png
6. Pixels:      python3 -c "PIL analysis"
7. DOM:         python3 dev-kit/cdp/cdp-eval.py '...diagnostics...'
8. Hypothesis:  correlate pixels with DOM → find the cause
9. Fix:         edit in styles.css or TerminalView.ts
10. Goto 1:     repeat for verification
```

## Screenshot report

When analyzing a screenshot, always respond in this structure:

1. **What is visible:** concrete description (where the blue blocks are, where the text is, whether there is overlap)
2. **Measurements:** pixel coordinates, sizes, offsets
3. **Hypotheses:** ranked by likelihood, with links to the KB
4. **Recommendation:** what to do, without auto-applying

## Related resources

- [[cdp-remote-debugging]] — CDP setup, raw WebSocket, Origin
- [[obsidian-css-overrides-position]] — Obsidian resets position to static
- `/terminal-debug` — general CDP debugging (eval, reload, open terminal)
- `dev-kit/cdp/cdp-screenshot.py` — screenshot capture
- `dev-kit/cdp/cdp-eval.py` — execute JS
- `autodocs/archive/knowledge-base/selection-fix-log.md` — log of selection fix attempts
