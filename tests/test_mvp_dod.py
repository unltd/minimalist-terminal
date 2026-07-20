"""
Direct pytest runner for all 7 MVP DoD items.
Bypasses Gauge/gRPC — calls CDP directly via conftest helpers.

Run:  pytest tests/test_mvp_dod.py -v

Timing note: each CDP call takes ~5.3 s (Docker→macOS host WebSocket).
All timeouts and poll intervals are calibrated to this latency.
"""

import json
import subprocess
import sys
import time

import pytest

# Ensure step_impl is importable
sys.path.insert(0, "tests/step_impl")
from conftest import cdp_eval, cdp_screenshot, CdpError  # noqa: E402


# ═══════════════════════════════════════════════════════════════════
# Timing constants (calibrated to ~5.3 s CDP latency)
# ═══════════════════════════════════════════════════════════════════

CDP_LATENCY = 5.5          # one CDP round-trip (seconds)
POLL_INTERVAL = 2.0        # between CDP retries (must be < latency to avoid wasted waits)
FAST_POLL = 1.0            # for short-retry loops (≤3 attempts)
PTY_SPAWN_WAIT = 4.0       # blind wait after opening terminal for PTY to spawn
PROMPT_TIMEOUT = 25        # max wait for shell prompt (allows 4–5 CDP calls)
TEXT_TIMEOUT = 20          # max wait for text to appear in buffer (~3 CDP calls)
FOCUS_TIMEOUT = 12         # max wait for autofocus (~2 CDP calls, spaced ~5s apart)


# ═══════════════════════════════════════════════════════════════════
# DoD #1: Plugin builds and loads
# ═══════════════════════════════════════════════════════════════════

def test_dod1_plugin_registered():
    """Плагин obsidian-terminal зарегистрирован в app.plugins.plugins."""
    result = cdp_eval("'obsidian-terminal' in app.plugins.plugins")
    assert result is True, f"Plugin not found. Available: {cdp_eval('Object.keys(app.plugins.plugins)')}"


def test_dod1_plugin_enabled():
    """Плагин obsidian-terminal включён."""
    result = cdp_eval(
        "app.plugins.plugins['obsidian-terminal'] && "
        "app.plugins.enabledPlugins.has('obsidian-terminal')"
    )
    assert result is True, "Plugin is not enabled"


def test_dod1_has_open_terminal_command():
    """Плагин имеет команду 'Open terminal'."""
    result = cdp_eval(
        "(function () {"
        "  var cmds = Object.values(app.commands.commands);"
        "  return cmds.some(function (c) { return c.id === 'obsidian-terminal:open-terminal'; });"
        "})()"
    )
    assert result is True, "Command 'obsidian-terminal:open-terminal' not registered"


def test_dod1_has_ribbon_icon():
    """Плагин имеет ribbon-icon 'terminal'."""
    result = cdp_eval(
        "(function () {"
        "  var items = document.querySelectorAll('.side-dock-ribbon-action');"
        "  for (var i = 0; i < items.length; i++) {"
        "    if (items[i].getAttribute('aria-label') === 'Open terminal') return true;"
        "  }"
        "  return false;"
        "})()"
    )
    assert result is True, "Ribbon icon 'Open terminal' not found"


# ═══════════════════════════════════════════════════════════════════
# DoD #2: Terminal opens via icon and Command Palette
# ═══════════════════════════════════════════════════════════════════

def test_dod2_open_via_command_palette():
    """Терминал открывается через Command Palette."""
    _close_all_terminal_leaves()
    cdp_eval("app.commands.executeCommandById('obsidian-terminal:open-terminal');")
    time.sleep(PTY_SPAWN_WAIT)
    count = cdp_eval("app.workspace.getLeavesOfType('obsidian-terminal-view').length")
    assert count >= 1, f"No terminal leaf found (count={count})"


def test_dod2_dom_has_xterm():
    """DOM содержит элемент xterm после открытия."""
    _ensure_terminal_open()
    result = cdp_eval("document.querySelector('.xterm') !== null")
    assert result is True, "No .xterm element in DOM"


def test_dod2_no_duplicate_on_reopen():
    """Повторное открытие не дублирует листья."""
    _close_all_terminal_leaves()
    cdp_eval("app.commands.executeCommandById('obsidian-terminal:open-terminal');")
    time.sleep(PTY_SPAWN_WAIT)
    cdp_eval("app.commands.executeCommandById('obsidian-terminal:open-terminal');")
    time.sleep(1.0)
    count = cdp_eval("app.workspace.getLeavesOfType('obsidian-terminal-view').length")
    assert count == 1, f"Expected 1 leaf, found {count}"


# ═══════════════════════════════════════════════════════════════════
# DoD #3: Shell works — commands execute, output is displayed
# ═══════════════════════════════════════════════════════════════════

def test_dod3_echo_command():
    """Команда echo выполняется и вывод отображается."""
    _ensure_terminal_open()
    _wait_for_prompt()
    _pty_write("echo hello_mvp_test\n")
    time.sleep(2.0)          # give the shell a moment to execute
    _wait_for_text("hello_mvp_test", timeout=TEXT_TIMEOUT)


def test_dod3_pwd_command():
    """Команда pwd выводит путь с '/'."""
    _ensure_terminal_open()
    _wait_for_prompt()
    _pty_write("pwd\n")
    time.sleep(1.0)
    _wait_for_text("/", timeout=TEXT_TIMEOUT)


def test_dod3_prompt_returns():
    """После команды возвращается приглашение."""
    _ensure_terminal_open()
    _wait_for_prompt()
    _pty_write("echo done\n")
    time.sleep(1.0)
    # After echo, the output line is "done", then a new prompt line appears.
    # With 5 s CDP latency, use longer interval and higher timeout.
    deadline = time.monotonic() + PROMPT_TIMEOUT
    while time.monotonic() < deadline:
        text = _terminal_buffer_text(lines=15)
        if text and any(p in text for p in ("$ ", "# ", "> ")):
            return
        time.sleep(POLL_INTERVAL)
    pytest.fail(f"Prompt did not return after command. Buffer: {_terminal_buffer_text(lines=15)}")


# ═══════════════════════════════════════════════════════════════════
# DoD #4: Text selection works correctly
# ═══════════════════════════════════════════════════════════════════

def test_dod4_selection_returns_text():
    """Программное выделение возвращает текст."""
    _ensure_terminal_open()
    _wait_for_prompt()
    _pty_write("echo selection_test_line\n")
    time.sleep(1.5)

    cdp_eval("""
        (function () {
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.term) throw new Error("Terminal not open");
            var buf = view.term.buffer.active;
            var endLine = Math.min(buf.length - 1, 10);
            if (endLine > 0) view.term.selectLines(0, endLine);
        })()
    """)
    time.sleep(0.5)

    selection = cdp_eval("""
        (function () {
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.term) return null;
            return view.term.getSelection();
        })()
    """)
    assert selection, "getSelection() returned empty"
    assert len(str(selection)) > 0, "Selection text is empty"


def test_dod4_xterm_screen_position_is_relative():
    """xterm-screen имеет position: relative (не переопределено Obsidian CSS)."""
    _ensure_terminal_open()
    pos = cdp_eval("""
        (function () {
            var screen = document.querySelector('.xterm-screen');
            return screen ? getComputedStyle(screen).position : null;
        })()
    """)
    assert pos == "relative", f".xterm-screen position is '{pos}', expected 'relative'"


def test_dod4_selection_layer_exists():
    """xterm-selection элементы существуют в DOM после выделения."""
    _ensure_terminal_open()
    _wait_for_prompt()
    _pty_write("echo make_selection_test\n")
    time.sleep(1.5)
    # Make a selection — xterm.js creates .xterm-selection divs
    cdp_eval("""
        (function () {
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.term) return;
            var buf = view.term.buffer.active;
            if (buf.length > 0) view.term.selectLines(0, Math.min(buf.length - 1, 3));
        })()
    """)
    time.sleep(0.5)
    exists = cdp_eval(
        "document.querySelectorAll('.xterm-selection').length > 0"
    )
    assert exists is True, ".xterm-selection elements not found in DOM after selection"


# ═══════════════════════════════════════════════════════════════════
# DoD #5: Scroll works
# ═══════════════════════════════════════════════════════════════════

def test_dod5_scroll_after_filling_buffer():
    """Скролл появляется после заполнения буфера."""
    _ensure_terminal_open()
    _wait_for_prompt()
    _pty_write("seq 1 100\n")
    time.sleep(4.0)  # generating 100 lines takes a moment

    # Check buffer has grown beyond visible rows
    rows = cdp_eval("""
        (function () {
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.term) return 0;
            return view.term.rows;
        })()
    """)
    buf_len = cdp_eval("""
        (function () {
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.term) return 0;
            return view.term.buffer.active.length;
        })()
    """)
    assert buf_len > rows, (
        f"Buffer length ({buf_len}) should exceed visible rows ({rows}) "
        "after generating output — scrollback should be active"
    )


def test_dod5_buffer_has_scrollback():
    """Буфер терминала содержит строки вывода."""
    _ensure_terminal_open()
    _wait_for_prompt()
    _pty_write("seq 1 50\n")
    time.sleep(2.5)

    length = cdp_eval("""
        (function () {
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.term) return 0;
            return view.term.buffer.active.length;
        })()
    """)
    assert length >= 50, f"Buffer length is {length}, expected >= 50"


# ═══════════════════════════════════════════════════════════════════
# DoD #6: Auto-focus on open
# ═══════════════════════════════════════════════════════════════════

def test_dod6_autofocus_on_open():
    """Терминал получает фокус после открытия."""
    _close_all_terminal_leaves()
    cdp_eval("""
        (function () {
            var leaf = app.workspace.getLeaf("split", "horizontal");
            leaf.setViewState({ type: "obsidian-terminal-view", active: true });
        })()
    """)
    time.sleep(PTY_SPAWN_WAIT)
    # Poll with intervals calibrated to CDP latency
    deadline = time.monotonic() + FOCUS_TIMEOUT
    while time.monotonic() < deadline:
        focused = cdp_eval("""
            (function () {
                var el = document.activeElement;
                return el && el.closest('.xterm') !== null;
            })()
        """)
        if focused:
            return
        time.sleep(FAST_POLL)

    active = cdp_eval(
        "document.activeElement ? document.activeElement.tagName : 'null'"
    )
    pytest.fail(f"Terminal did not get focus. Active: {active}")


def test_dod6_active_element_is_textarea():
    """Активный элемент — textarea внутри xterm."""
    _ensure_terminal_open()
    cdp_eval("""
        (function () {
            var el = document.querySelector('.xterm-textarea');
            if (el) el.focus();
        })()
    """)
    time.sleep(0.3)

    result = cdp_eval("""
        (function () {
            var el = document.activeElement;
            if (!el) return {};
            return {
                tag: el.tagName,
                inXterm: el.closest('.xterm') !== null,
            };
        })()
    """)
    assert result.get("inXterm") is True, f"Active element not in xterm: {result}"


# ═══════════════════════════════════════════════════════════════════
# DoD #7: Close on Ctrl+D — no zombie processes
# ═══════════════════════════════════════════════════════════════════

def test_dod7_close_by_exit_no_zombies():
    """Закрытие по exit не оставляет зомби."""
    _ensure_terminal_open()
    _wait_for_prompt()
    _pty_write("exit\n")

    # Wait for leaf to close (with CDP-latency-aware intervals)
    for _ in range(10):
        time.sleep(FAST_POLL)
        count = cdp_eval("app.workspace.getLeavesOfType('obsidian-terminal-view').length")
        if count == 0:
            break
    else:
        pytest.fail("Terminal leaf not removed after exit")

    time.sleep(2.0)
    _assert_no_zombie_processes()


def test_dod7_close_by_api_no_zombies():
    """Закрытие через workspace.detachLeavesOfType не оставляет зомби."""
    _ensure_terminal_open()
    _wait_for_prompt()
    cdp_eval("app.workspace.detachLeavesOfType('obsidian-terminal-view');")

    for _ in range(6):
        time.sleep(FAST_POLL)
        count = cdp_eval("app.workspace.getLeavesOfType('obsidian-terminal-view').length")
        if count == 0:
            break
    else:
        pytest.fail("Terminal leaf not removed after detach")

    time.sleep(2.0)
    _assert_no_zombie_processes()


# ═══════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════

def _close_all_terminal_leaves():
    cdp_eval("app.workspace.detachLeavesOfType('obsidian-terminal-view');")
    time.sleep(0.5)


def _ensure_terminal_open():
    """Close any existing terminal, open a fresh one, wait for PTY spawn.

    Does NOT do extra CDP readiness checks — _wait_for_prompt() serves
    as the natural readiness gate (it polls until the shell prompt appears).
    """
    cdp_eval("app.workspace.detachLeavesOfType('obsidian-terminal-view');")
    time.sleep(0.5)
    cdp_eval("""
        (function () {
            var leaf = app.workspace.getLeaf("split", "horizontal");
            leaf.setViewState({ type: "obsidian-terminal-view", active: true });
        })()
    """)
    time.sleep(PTY_SPAWN_WAIT)


def _pty_write(data: str):
    """Write data to the PTY via a JS double-quoted string.

    Uses explicit \\n escape sequence — avoids literal newlines in JS source
    which cause SyntaxError (silently swallowed by older cdp-eval.py).
    """
    # Strip trailing newline — we add explicit \\n in JS
    text = data.rstrip("\n")
    # Escape for double-quoted JS string: backslash, double-quote, newline, etc.
    escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    cdp_eval(f"""
        (function () {{
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.pty) throw new Error("Terminal not open");
            view.pty.write("{escaped}\\n");
        }})()
    """)


def _wait_for_prompt(timeout: int = PROMPT_TIMEOUT):
    """Poll terminal buffer until a shell prompt character ($, #, >) is found."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
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
            if text and isinstance(text, str) and any(c in text for c in "$#>"):
                return
        except CdpError:
            pass
        time.sleep(POLL_INTERVAL)
    # One last check for diagnostics
    last = _terminal_buffer_text(lines=10)
    pytest.fail(f"Prompt not found within {timeout}s. Last buffer lines:\n{last}")


def _wait_for_text(search: str, timeout: int = TEXT_TIMEOUT):
    """Poll terminal buffer until `search` appears in recent output."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            text = cdp_eval("""
                (function () {
                    var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
                    if (!view || !view.term) return "";
                    var buf = view.term.buffer.active;
                    var lines = [];
                    for (var i = Math.max(0, buf.length - 25); i < buf.length; i++) {
                        var line = buf.getLine(i);
                        if (line) lines.push(line.translateToString());
                    }
                    return lines.join("\\n");
                })()
            """)
            if search in str(text):
                return
        except CdpError:
            pass
        time.sleep(POLL_INTERVAL)
    # Diagnostic: show what we have
    last = _terminal_buffer_text(lines=20)
    pytest.fail(f"'{search}' not found in terminal output within {timeout}s. Buffer:\n{last}")


def _terminal_buffer_text(lines: int = 10) -> str:
    """Get last N lines of terminal buffer as text."""
    try:
        return str(cdp_eval(f"""
            (function () {{
                var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
                if (!view || !view.term) return "";
                var buf = view.term.buffer.active;
                var out = [];
                for (var i = Math.max(0, buf.length - {lines}); i < buf.length; i++) {{
                    var line = buf.getLine(i);
                    if (line) out.push(line.translateToString());
                }}
                return out.join("\\n");
            }})()
        """))
    except CdpError:
        return ""


def _assert_no_zombie_processes():
    try:
        proc = subprocess.run(
            ["pgrep", "-f", "node-pty"],
            capture_output=True, text=True, timeout=5,
        )
        zombies = [p for p in proc.stdout.strip().splitlines() if p.strip()]
        assert len(zombies) == 0, f"Zombie node-pty processes: {zombies}"
    except FileNotFoundError:
        pass

    try:
        proc = subprocess.run(
            ["ps", "aux"],
            capture_output=True, text=True, timeout=5,
        )
        pty_lines = [
            l for l in proc.stdout.splitlines()
            if "node-pty" in l and "grep" not in l
        ]
        assert len(pty_lines) == 0, f"Zombie node-pty processes: {pty_lines}"
    except FileNotFoundError:
        pass
