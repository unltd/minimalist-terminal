"""
Step implementations for shell-exec.spec — DoD #3: shell executes
commands and displays output.
"""

import time

from getgauge.python import step

from conftest import cdp_eval, wait_for


@step("Открыть терминал")
def open_terminal():
    cdp_eval("""
        (function () {
            var leaves = app.workspace.getLeavesOfType("obsidian-terminal-view");
            if (leaves.length === 0) {
                var leaf = app.workspace.getLeaf("split", "horizontal");
                leaf.setViewState({ type: "obsidian-terminal-view", active: true });
            } else {
                app.workspace.revealLeaf(leaves[0]);
            }
        })()
    """)
    # Allow time for terminal to initialize and shell to start
    time.sleep(2.0)


@step("Дождаться приглашения командной строки длительностью до <seconds> секунд")
def wait_for_prompt(seconds: str):
    timeout_ms = int(seconds) * 1000

    # The terminal buffer should contain a prompt character ($, #, or >)
    # after shell startup. We check the last non-empty line.
    def buffer_has_prompt() -> bool:
        try:
            text = cdp_eval("""
                (function () {
                    var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
                    if (!view || !view.term) return false;
                    var buf = view.term.buffer.active;
                    for (var i = buf.length - 1; i >= 0; i--) {
                        var line = buf.getLine(i);
                        if (line && line.translateToString().trim()) {
                            return line.translateToString();
                        }
                    }
                    return false;
                })()
            """)
            if text and isinstance(text, str):
                return any(c in text for c in "$#>")
        except Exception:
            pass
        return False

    deadline = time.monotonic() + timeout_ms / 1000
    while time.monotonic() < deadline:
        if buffer_has_prompt():
            return
        time.sleep(0.3)

    raise AssertionError(f"Prompt not found within {seconds}s")


@step('Ввести команду <command>')
def type_command(command: str):
    """Write a command to the PTY, followed by newline."""
    cdp_eval(f"""
        (function () {{
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.pty) throw new Error("Terminal not open");
            view.pty.write({command!r} + "\\n");
        }})()
    """)


@step("В течение <seconds> секунд вывод содержит <expected>")
def output_contains_within(seconds: str, expected: str):
    timeout_ms = int(seconds) * 1000
    deadline = time.monotonic() + timeout_ms / 1000

    while time.monotonic() < deadline:
        text = cdp_eval("""
            (function () {
                var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
                if (!view || !view.term) return "";
                var buf = view.term.buffer.active;
                var lines = [];
                for (var i = Math.max(0, buf.length - 20); i < buf.length; i++) {
                    var line = buf.getLine(i);
                    if (line) lines.push(line.translateToString());
                }
                return lines.join("\\n");
            })()
        """)
        if expected in str(text):
            return
        time.sleep(0.3)

    raise AssertionError(f"'{expected}' not found in terminal output within {seconds}s")


@step("В течение <seconds> секунд терминал показывает новое приглашение командной строки")
def prompt_returns(seconds: str):
    """After a command, a new prompt should appear."""
    timeout_ms = int(seconds) * 1000
    deadline = time.monotonic() + timeout_ms / 1000

    while time.monotonic() < deadline:
        text = cdp_eval("""
            (function () {
                var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
                if (!view || !view.term) return "";
                var buf = view.term.buffer.active;
                var last = buf.getLine(buf.length - 1);
                return last ? last.translateToString() : "";
            })()
        """)
        if text and any(c in str(text) for c in "$#>"):
            return
        time.sleep(0.3)

    raise AssertionError(f"Prompt did not return within {seconds}s")
