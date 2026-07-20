"""
Step implementations for open-terminal.spec — DoD #2: terminal opens
via ribbon icon and Command Palette.
"""

from getgauge.python import step

from conftest import cdp_eval


@step("Закрыть все листья терминала")
def close_all_terminal_leaves():
    cdp_eval(
        "app.workspace.detachLeavesOfType('obsidian-terminal-view');"
    )


@step('Выполнить команду "obsidian-terminal:open-terminal"')
def run_open_terminal_command():
    cdp_eval(
        "app.commands.executeCommandById('obsidian-terminal:open-terminal');"
    )


@step('В workspace есть лист с типом "obsidian-terminal-view"')
def workspace_has_terminal_leaf():
    result = cdp_eval(
        "app.workspace.getLeavesOfType('obsidian-terminal-view').length > 0"
    )
    assert result is True, "No leaf of type 'obsidian-terminal-view' in workspace"


@step('DOM содержит элемент с классом "xterm"')
def dom_has_xterm_element():
    result = cdp_eval(
        "document.querySelector('.xterm') !== null"
    )
    assert result is True, "No .xterm element found in DOM"


@step('В workspace ровно 1 лист с типом "obsidian-terminal-view"')
def workspace_has_exactly_one_terminal_leaf():
    count = cdp_eval(
        "app.workspace.getLeavesOfType('obsidian-terminal-view').length"
    )
    assert count == 1, f"Expected 1 leaf, found {count}"
