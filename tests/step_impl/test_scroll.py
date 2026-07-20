"""
Step implementations for scroll.spec — DoD #5: terminal scroll works.
"""

import time

from getgauge.python import step

from conftest import cdp_eval


@step("Ввести команду для генерации <count> строк вывода")
def generate_output_lines(count: str):
    n = int(count)
    # Generate N lines of output via seq or printf
    cdp_eval(f"""
        (function () {{
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.pty) throw new Error("Terminal not open");
            view.pty.write("for i in $(seq 1 {n}); do echo line_$i; done\\n");
        }})()
    """)
    # Wait for all lines to be printed (rough estimate: 100 lines/s)
    wait = max(0.5, n / 100)
    time.sleep(wait)


@step("Вьюпорт терминала имеет ненулевой scrollTop")
def viewport_has_scroll():
    scroll_top = cdp_eval("""
        (function () {
            var vp = document.querySelector('.xterm-viewport');
            if (!vp) return null;
            return vp.scrollTop;
        })()
    """)
    assert scroll_top is not None, ".xterm-viewport not found in DOM"
    assert scroll_top > 0, f"Expected scrollTop > 0, got {scroll_top}"


@step("Длина буфера терминала больше 0")
def buffer_length_positive():
    length = cdp_eval("""
        (function () {
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.term) return 0;
            return view.term.buffer.active.length;
        })()
    """)
    assert length > 0, "Terminal buffer length is 0"


@step("Длина буфера терминала не меньше <count>")
def buffer_length_at_least(count: str):
    expected = int(count)
    actual = cdp_eval("""
        (function () {
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.term) return 0;
            return view.term.buffer.active.length;
        })()
    """)
    assert actual >= expected, f"Buffer length {actual} < {expected}"
