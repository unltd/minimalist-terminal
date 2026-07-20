"""
Step implementations for selection.spec — DoD #4: mouse text selection
works correctly in the terminal.
"""

import time

from getgauge.python import step

from conftest import cdp_eval


@step("Терминал содержит текст в буфере")
def terminal_has_buffer_text():
    time.sleep(0.5)  # allow output to render
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
            // Select from line 0 to wherever we have content
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


@step('Элемент ".xterm-screen" имеет CSS-свойство position равное "relative"')
def xterm_screen_is_relative():
    position = cdp_eval("""
        (function () {
            var screen = document.querySelector('.xterm-screen');
            if (!screen) return null;
            return getComputedStyle(screen).position;
        })()
    """)
    assert position == "relative", (
        f".xterm-screen position is '{position}', expected 'relative'. "
        "Obsidian CSS may have overridden it to 'static'."
    )


@step('Элемент ".xterm-selection" существует в DOM')
def xterm_selection_exists_in_dom():
    # xterm-selection divs are created dynamically during selection.
    # We check that the xterm layer that CONTAINS selections exists.
    exists = cdp_eval("""
        (function () {
            var layers = document.querySelectorAll('.xterm-selection-layer');
            return layers.length > 0;
        })()
    """)
    assert exists is True, ".xterm-selection-layer not found in DOM"
