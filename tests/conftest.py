"""
Shared fixtures for Minimalist Terminal tests.

Provides:
- cdp_eval(js)    — execute JS in Obsidian via CDP, return parsed result
- cdp_screenshot() — capture a screenshot of the Obsidian window
- wait_for(cond)  — poll until a JS condition is true

CDP connection uses the existing scripts/cdp-eval.py and cdp-screenshot.py.
When running from a Docker container (claudocker), CDP_HOST defaults to the
Docker host IP (192.168.65.254). On macOS host, set CDP_HOST=127.0.0.1.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
CDP_EVAL = str(PROJECT_ROOT / "scripts" / "cdp-eval.py")
CDP_SCREENSHOT = str(PROJECT_ROOT / "scripts" / "cdp-screenshot.py")


class CdpError(RuntimeError):
    """Raised when a CDP call fails."""


def cdp_eval(expression: str, timeout: int = 30) -> object:
    """Execute a JavaScript expression in Obsidian and return the result.

    The expression runs in the Obsidian renderer context — full access to
    `app`, `document`, plugin APIs, and xterm.js internals.

    Returns the JSON-decoded value (str, int, bool, list, dict, or None).
    """
    env = os.environ.copy()
    # Propagate CDP_HOST if set, otherwise script uses its built-in default
    if "CDP_HOST" in os.environ:
        env["CDP_HOST"] = os.environ["CDP_HOST"]
    # Default vault for testing
    if "CDP_VAULT" not in env:
        env["CDP_VAULT"] = "obsidian-test"

    proc = subprocess.run(
        [sys.executable, CDP_EVAL, expression],
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
        cwd=PROJECT_ROOT,
    )

    if proc.returncode != 0:
        stderr = proc.stderr.strip()
        stdout = proc.stdout.strip()
        raise CdpError(
            f"cdp-eval failed (exit {proc.returncode}):\n"
            f"  stdout: {stdout}\n"
            f"  stderr: {stderr}"
        )

    output = proc.stdout.strip()
    if not output:
        return None

    try:
        parsed = json.loads(output)
    except json.JSONDecodeError:
        # Some results are plain strings (e.g. terminal text output)
        return output

    # Unwrap CDP response: {"result": {"type": "...", "value": ...}} → value
    if isinstance(parsed, dict) and "result" in parsed:
        result = parsed["result"]
        if isinstance(result, dict) and "value" in result:
            return result["value"]
        return result
    return parsed


def cdp_screenshot(filename: str | None = None) -> str:
    """Take a screenshot of the Obsidian window via CDP.

    Returns the path to the saved screenshot file.
    """
    env = os.environ.copy()
    if "CDP_HOST" in os.environ:
        env["CDP_HOST"] = os.environ["CDP_HOST"]
    if "CDP_VAULT" not in env:
        env["CDP_VAULT"] = "obsidian-test"

    args = [sys.executable, CDP_SCREENSHOT]
    if filename:
        args.append(filename)

    proc = subprocess.run(
        args,
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
        cwd=PROJECT_ROOT,
    )

    if proc.returncode != 0:
        raise CdpError(f"cdp-screenshot failed: {proc.stderr.strip()}")

    # Parse "Screenshot saved: /path/to/file.png (N bytes)" from stdout
    for line in proc.stdout.splitlines():
        if "Screenshot saved:" in line:
            return line.split("Screenshot saved:")[1].split("(")[0].strip()

    raise CdpError(f"Could not parse screenshot path from: {proc.stdout}")


def wait_for(condition_js: str, timeout_ms: int = 5000, poll_ms: int = 100) -> bool:
    """Poll a JS condition until it's true or timeout expires.

    The condition should be a JS expression that evaluates to truthy/falsy.
    Returns True if the condition became true, False on timeout.
    """
    deadline = time.monotonic() + timeout_ms / 1000
    while time.monotonic() < deadline:
        try:
            result = cdp_eval(condition_js)
            if result:
                return True
        except CdpError:
            pass  # Obsidian might not be ready yet
        time.sleep(poll_ms / 1000)
    return False


# ---------------------------------------------------------------------------
# pytest fixtures (used when running pytest directly, without Gauge)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def obsidian_available() -> bool:
    """Check if Obsidian is reachable via CDP. Skip all tests if not."""
    try:
        cdp_eval("1 + 1", timeout=5)
        return True
    except CdpError:
        return False


@pytest.fixture(autouse=True)
def _skip_if_no_obsidian(obsidian_available: bool):
    """Auto-skip tests when Obsidian is not reachable (e.g. in CI)."""
    if not obsidian_available:
        pytest.skip("Obsidian CDP not reachable — is it running with --remote-debugging-port=9222?")


@pytest.fixture
def term_view():
    """Return a JS expression that resolves to the active TerminalView."""
    cdp_eval("""
        (function () {
            var leaf = app.workspace.getLeavesOfType("minimalist-terminal-view")[0];
            if (!leaf) {
                leaf = app.workspace.getLeaf("split", "horizontal");
            }
            leaf.setViewState({ type: "minimalist-terminal-view", active: true });
        })()
    """)
    # Give the terminal time to open and initialize
    time.sleep(1.5)
    return True


@pytest.fixture
def assert_no_zombies():
    """Check that no orphaned node-pty processes exist."""
    yield
    # After test: check for zombies
    proc = subprocess.run(
        ["pgrep", "-f", "node-pty"],
        capture_output=True,
        text=True,
    )
    zombies = [p for p in proc.stdout.strip().splitlines() if p.strip()]
    if zombies:
        pytest.fail(f"Zombie PTY processes found: {zombies}")
