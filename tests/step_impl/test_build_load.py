"""
Step implementations for build-load.spec — DoD #1: plugin builds and loads.
"""

from getgauge.python import step

from conftest import cdp_eval, CdpError


@step("Плагин obsidian-terminal зарегистрирован в app.plugins.plugins")
def plugin_is_registered():
    result = cdp_eval("'obsidian-terminal' in app.plugins.plugins")
    assert result is True, (
        f"Plugin 'obsidian-terminal' not found in app.plugins.plugins. "
        f"Available: {cdp_eval('Object.keys(app.plugins.plugins)')}"
    )


@step("Плагин obsidian-terminal включён (enabled)")
def plugin_is_enabled():
    result = cdp_eval(
        "app.plugins.plugins['obsidian-terminal'] && "
        "app.plugins.enabledPlugins.has('obsidian-terminal')"
    )
    assert result is True, "Plugin is not enabled"


@step('Плагин имеет команду "Open terminal"')
def plugin_has_command():
    result = cdp_eval(
        "(function () {"
        "  var cmds = Object.values(app.commands.commands);"
        "  return cmds.some(function (c) { return c.id === 'obsidian-terminal:open-terminal'; });"
        "})()"
    )
    assert result is True, "Command 'obsidian-terminal:open-terminal' not registered"


@step('Плагин имеет ribbon-icon "terminal"')
def plugin_has_ribbon_icon():
    # Ribbon icons are added via addRibbonIcon — check by DOM query
    result = cdp_eval(
        "(function () {"
        "  var items = document.querySelectorAll('.side-dock-ribbon-action');"
        "  for (var i = 0; i < items.length; i++) {"
        "    if (items[i].getAttribute('aria-label') === 'Open terminal') return true;"
        "  }"
        "  return false;"
        "})()"
    )
    assert result is True, "Ribbon icon 'Open terminal' not found in DOM"
