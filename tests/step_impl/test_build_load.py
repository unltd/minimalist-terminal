"""
Step implementations for build-load.spec — DoD #1: plugin builds and loads.
"""

from getgauge.python import step

from conftest import cdp_eval


@step("Plugin minimalist-terminal is registered in app.plugins.plugins")
def plugin_is_registered():
    result = cdp_eval("'minimalist-terminal' in app.plugins.plugins")
    assert result is True, (
        f"Plugin 'minimalist-terminal' not found in app.plugins.plugins. "
        f"Available: {cdp_eval('Object.keys(app.plugins.plugins)')}"
    )


@step("Plugin minimalist-terminal is enabled")
def plugin_is_enabled():
    result = cdp_eval(
        "app.plugins.plugins['minimalist-terminal'] && "
        "app.plugins.enabledPlugins.has('minimalist-terminal')"
    )
    assert result is True, "Plugin is not enabled"


@step("Plugin has command <command_name>")
def plugin_has_command(command_name: str):
    cmd_id = _command_id_for(command_name)
    result = cdp_eval(
        "(function () {"
        "  var cmds = Object.values(app.commands.commands);"
        f"  return cmds.some(function (c) {{ return c.id === '{cmd_id}'; }});"
        "})()"
    )
    assert result is True, f"Command '{cmd_id}' not registered"


@step("Plugin has ribbon-icon <icon_name>")
def plugin_has_ribbon_icon(icon_name: str):
    label = _ribbon_label_for(icon_name)
    result = cdp_eval(
        "(function () {"
        "  var items = document.querySelectorAll('.side-dock-ribbon-action');"
        f"  for (var i = 0; i < items.length; i++) {{"
        f"    if (items[i].getAttribute('aria-label') === '{label}') return true;"
        f"  }}"
        "  return false;"
        "})()"
    )
    assert result is True, f"Ribbon icon '{label}' not found in DOM"


def _command_id_for(name: str) -> str:
    return {"Open terminal": "minimalist-terminal:open-terminal"}.get(name, name)


def _ribbon_label_for(name: str) -> str:
    return {"terminal": "Open terminal"}.get(name, name)
