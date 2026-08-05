"""
Step implementations for close-no-zombie.spec — DoD #7: closing terminal
via Ctrl+D (exit) leaves no zombie processes.
"""

import subprocess
import time

from getgauge.python import step

from conftest import cdp_eval


@step("Send command <command> to terminal with newline")
def send_command_with_newline(command: str):
    cdp_eval(f"""
        (function () {{
            var view = app.workspace.getLeavesOfType("minimalist-terminal-view")[0]?.view;
            if (!view || !view.pty) throw new Error("Terminal not open");
            view.pty.write({command!r} + "\\n");
        }})()
    """)


@step("Within <seconds> seconds the terminal leaf is removed from workspace")
def terminal_leaf_removed(seconds: str):
    timeout_ms = int(seconds) * 1000
    deadline = time.monotonic() + timeout_ms / 1000

    while time.monotonic() < deadline:
        count = cdp_eval(
            "app.workspace.getLeavesOfType('minimalist-terminal-view').length"
        )
        if count == 0:
            return
        time.sleep(0.3)

    raise AssertionError(
        f"Terminal leaf still present after {seconds}s"
    )


@step("No node-pty processes in the system")
def no_node_pty_processes():
    time.sleep(1.0)

    # Try pgrep first (macOS/Linux)
    try:
        proc = subprocess.run(
            ["pgrep", "-f", "node-pty"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        zombies = [p for p in proc.stdout.strip().splitlines() if p.strip()]
        assert len(zombies) == 0, f"Zombie node-pty processes found: {zombies}"
    except FileNotFoundError:
        pass

    # Fallback: ps aux | grep
    try:
        proc = subprocess.run(
            ["ps", "aux"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        pty_lines = [
            line for line in proc.stdout.splitlines()
            if "node-pty" in line and "grep" not in line
        ]
        assert len(pty_lines) == 0, f"Zombie node-pty processes found: {pty_lines}"
    except FileNotFoundError:
        pass


@step("Close all terminal leaves via workspace API")
def close_all_terminal_leaves_via_api():
    cdp_eval(
        "app.workspace.detachLeavesOfType('minimalist-terminal-view');"
    )
