# Contributing to Obsidian Terminal

## Setup

```bash
git clone https://github.com/unltd/obsidian-terminal.git
cd obsidian-terminal
npm install
```

## Development

```bash
npm run dev      # Watch mode (~30 ms rebuilds)
npm run build    # Type-check + production bundle
```

For CDP-based browser testing (Gauge + pytest), see [CLAUDE.md](CLAUDE.md).

## Before submitting a PR

1. Run `npm run build` — verify no type errors
2. Test the plugin manually in a vault (install via symlink or clone into `.obsidian/plugins/`)
3. If adding a feature, consider adding a test spec in `tests/specs/`

## Commit conventions

- Use English for commit messages
- Follow: `type: description` (e.g. `fix: focus wrestling after tab switch`)
- Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`

## PR checklist

- [ ] Code compiles with `npm run build`
- [ ] Tested in Obsidian on macOS
- [ ] CSS changes don't break xterm.js rendering
- [ ] New dependencies are minimal and justified
