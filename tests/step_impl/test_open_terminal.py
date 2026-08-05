"""
Step implementations for open-terminal.spec — DoD #2: terminal opens
via ribbon icon and Command Palette.
"""

from getgauge.python import step

from conftest import cdp_eval


@step("Close all terminal leaves")
def close_all_terminal_leaves():
    cdp_eval(
        "app.workspace.detachLeavesOfType('minimalist-terminal-view');"
    )


@step("Execute command <command_id>")
def run_command_by_id(command_id: str):
    cdp_eval(
        f"app.commands.executeCommandById('{command_id}');"
    )


@step("Workspace has a leaf of type <view_type>")
def workspace_has_terminal_leaf(view_type: str):
    result = cdp_eval(
        f"app.workspace.getLeavesOfType('{view_type}').length > 0"
    )
    assert result is True, f"No leaf of type '{view_type}' in workspace"


@step("DOM contains element with class <class_name>")
def dom_has_element_with_class(class_name: str):
    result = cdp_eval(
        f"document.querySelector('{class_name}') !== null"
    )
    assert result is True, f"No '{class_name}' element found in DOM"


@step("Workspace has exactly <count> leaf of type <view_type>")
def workspace_has_exactly_n_leaves(count: str, view_type: str):
    expected = int(count)
    found = cdp_eval(
        f"app.workspace.getLeavesOfType('{view_type}').length"
    )
    assert found == expected, f"Expected {expected} leaf, found {found}"
