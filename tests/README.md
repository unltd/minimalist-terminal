# Minimalist Terminal — Test Suite

Gauge + pytest tests for the Minimalist Terminal plugin. Specifications are in Markdown (`.spec`), step implementations in Python/pytest.

## Structure

```
tests/
├── manifest.json              — Gauge project
├── env/default/
│   └── python.properties      — Python runner config
├── specs/                     — Gauge .spec files (Markdown)
│   └── mvp/                   — tests for the MVP Definition of Done
│       ├── build-load.spec
│       ├── open-terminal.spec
│       ├── shell-exec.spec
│       ├── selection.spec
│       ├── scroll.spec
│       ├── autofocus.spec
│       └── close-no-zombie.spec
├── step_impl/                 — pytest step implementations
│   ├── conftest.py            — shared fixtures and CDP client
│   └── test_*.py              — one file per .spec
└── README.md                  — this file
```

## Dependencies

```bash
# Gauge CLI
brew install gauge

# Gauge Python plugin
gauge install python

# Python dependencies
pip install getgauge pytest
```

## Running Obsidian with CDP

Tests require a running Obsidian instance with remote debugging:

```bash
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*
```

**Important:** Obsidian must be started **before** the tests. Gauge fixtures connect to an already-running instance.

### From a Docker container (claudocker)

CDP scripts connect to the host via `192.168.65.254:9222` by default. If Obsidian is running on the macOS host, everything should work automatically.

### From the macOS host

Set the environment variable so the scripts use localhost:

```bash
export CDP_HOST=127.0.0.1
```

## Running tests

### All MVP tests via Gauge

```bash
gauge run tests/specs/mvp/
```

### A specific specification

```bash
gauge run tests/specs/mvp/shell-exec.spec
```

### By tags

```bash
gauge run --tags "doD-3" tests/specs/
gauge run --tags "cdp" tests/specs/
```

### Dry-run (structure validation, no execution)

```bash
gauge run --dry-run tests/specs/
```

### Directly via pytest (without Gauge)

```bash
pytest tests/step_impl/ -v
```

## Tags

Each `.spec` file is tagged:

| Tag | Meaning |
|-----|----------|
| `mvp` | MVP test |
| `doD-1` … `doD-7` | Which DoD item is verified |
| `cdp` | Automated via CDP |
| `visual` | Requires visual verification (screenshot) |

## How to add a new test

1. Create a `.spec` file in `tests/specs/<feature>/`
2. Describe scenarios in Gauge Markdown
3. Create `test_*.py` in `tests/step_impl/` with `@step` decorators
4. Run: `gauge run tests/specs/<feature>/`

Existing steps (from `conftest.py` and other `test_*.py`) are reused automatically — Gauge finds the `@step` by text.

## Limitations

- **Local only.** Tests require a real Obsidian with a GUI — CI is impossible without display emulation
- **Single Obsidian instance.** CDP scripts connect to the first `app://obsidian.md` window
- **macOS.** The `open -a Obsidian` command is macOS-specific
- **Instability.** Obsidian may change internal command IDs and the DOM structure — tests need updates on major releases
