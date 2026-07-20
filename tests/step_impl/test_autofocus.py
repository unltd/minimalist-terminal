"""
Step implementations for autofocus.spec — DoD #6: terminal auto-focuses on open.
"""

import time

from getgauge.python import step

from conftest import cdp_eval


@step("В течение <seconds> секунд терминал получает фокус")
def terminal_gets_focus_within(seconds: str):
    timeout_ms = int(seconds) * 1000
    deadline = time.monotonic() + timeout_ms / 1000

    while time.monotonic() < deadline:
        focused = cdp_eval("""
            (function () {
                var el = document.activeElement;
                if (!el) return false;
                return el.closest('.xterm') !== null;
            })()
        """)
        if focused:
            return
        time.sleep(0.2)

    active = cdp_eval("""
        (function () {
            var el = document.activeElement;
            if (!el) return 'null';
            return el.tagName + '.' + el.className + ' in ' + (el.closest('.xterm') ? 'xterm' : 'not-xterm');
        })()
    """)
    raise AssertionError(
        f"Terminal did not get focus within {seconds}s. "
        f"Active element: {active}"
    )


@step("Активный элемент — textarea внутри xterm")
def active_element_is_xterm_textarea():
    result = cdp_eval("""
        (function () {
            var el = document.activeElement;
            if (!el) return 'no-active-element';
            return {
                tag: el.tagName,
                inXterm: el.closest('.xterm') !== null,
                isTextarea: el.tagName === 'TEXTAREA',
            };
        })()
    """)
    assert result["inXterm"] is True, (
        f"Active element is not inside .xterm: tag={result['tag']}"
    )
    assert result["isTextarea"] is True, (
        f"Active element is not a textarea: tag={result['tag']}"
    )


@step("Кликнуть в контейнер терминала")
def click_terminal_container():
    cdp_eval("""
        (function () {
            var container = document.querySelector('.terminal-container');
            if (!container) throw new Error('.terminal-container not found');
            container.click();
            var evt = new MouseEvent('mousedown', { bubbles: true, cancelable: true });
            container.dispatchEvent(evt);
        })()
    """)
    time.sleep(0.3)
