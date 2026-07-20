"""
Step implementations for selection.spec — DoD #4: mouse text selection
works correctly in the terminal.
"""

import time

from getgauge.python import step

from conftest import cdp_eval


@step("Терминал содержит текст в буфере")
def terminal_has_buffer_text():
    time.sleep(0.5)
    length = cdp_eval("""
        (function () {
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.term) return 0;
            return view.term.buffer.active.length;
        })()
    """)
    assert length > 0, "Terminal buffer is empty"


@step("Программное выделение через term.selectLines возвращает непустой текст")
def select_lines_returns_text():
    cdp_eval("""
        (function () {
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.term) throw new Error("Terminal not open");
            var buf = view.term.buffer.active;
            var endLine = Math.min(buf.length - 1, 10);
            if (endLine > 0) {
                view.term.selectLines(0, endLine);
            }
        })()
    """)
    time.sleep(0.3)

    selection = cdp_eval("""
        (function () {
            var view = app.workspace.getLeavesOfType("obsidian-terminal-view")[0]?.view;
            if (!view || !view.term) return null;
            return view.term.getSelection();
        })()
    """)

    assert selection, "getSelection() returned empty or null"
    assert len(str(selection)) > 0, "Selection text is empty"


@step("CSS-свойство position элемента <selector> равно <expected>")
def element_position_equals(selector: str, expected: str):
    actual = cdp_eval(f"""
        (function () {{
            var el = document.querySelector({selector!r});
            if (!el) return null;
            return getComputedStyle(el).position;
        }})()
    """)
    assert actual == expected, (
        f"{selector} position is '{actual}', expected '{expected}'. "
        "Obsidian CSS may have overridden it."
    )


@step("DOM содержит селектор <selector>")
def dom_contains_selector(selector: str):
    exists = cdp_eval(
        f"(function () {{ return document.querySelectorAll({selector!r}).length > 0; }})()"
    )
    assert exists is True, f"'{selector}' not found in DOM"
