# Minimalist Terminal — Test Suite

pytest + CDP tests for the Minimalist Terminal plugin. All checks run against a live Obsidian instance over Chrome DevTools Protocol.

## Structure

```
tests/
├── conftest.py        — shared CDP client (cdp_eval, cdp_screenshot, wait_for) + skip fixture
├── test_mvp_dod.py    — the 7 MVP Definition-of-Done checks
└── README.md          — this file
```

## Dependencies

```bash
pip install pytest
```

## Running Obsidian with CDP

Tests require a running Obsidian instance with remote debugging:

```bash
open -a Obsidian --args --remote-debugging-port=9222 --remote-allow-origins=*
```

**Important:** Obsidian must be started **before** the tests and opened on the target vault (the vault is matched by name via the `CDP_VAULT` env var, default `obsidian-test`). The plugin under test must be installed in `.obsidian/plugins/minimalist-terminal/` and enabled.

### From a Docker container (claudocker)

CDP scripts connect to the host via `192.168.65.254:9222` by default. If Obsidian is running on the macOS host, everything should work automatically.

### From the macOS host

Set the environment variable so the scripts use localhost:

```bash
export CDP_HOST=127.0.0.1
```

## Running tests

```bash
pytest tests/test_mvp_dod.py -v
```

If Obsidian is not reachable via CDP, all tests are auto-skipped (see the `_skip_if_no_obsidian` fixture).

## How to add a new test

1. Add a `test_dod<N>_<name>()` function to `tests/test_mvp_dod.py`
2. Use the `cdp_eval()` helper to execute JS in Obsidian (open a terminal, inspect the DOM, run a shell command)
3. Reuse helpers: `_ensure_terminal_open()`, `_wait_for_prompt()`, `_pty_write()`

## Limitations

- **Local only.** Tests require a real Obsidian with a GUI — CI is impossible without display emulation
- **CDP latency.** Each `cdp_eval()` round-trip takes ~5 s from the container to the macOS host — timeouts are calibrated to this
- **Host-dependent shell.** Tests detect the shell prompt by `%`, `$`, `#`, `>` characters (zsh default on macOS)
- **Instability.** Obsidian may change internal command IDs and the DOM structure — tests need updates on major releases
