# Open Terminal

Verifies opening the terminal: via the ribbon icon and via the Command Palette.

## Open via Command Palette
tags: mvp, doD-2, cdp

* Close all terminal leaves
* Execute command "minimalist-terminal:open-terminal"
* Workspace has a leaf of type "minimalist-terminal-view"
* DOM contains element with class "xterm"

## Reopening does not duplicate
tags: mvp, doD-2, cdp

* Close all terminal leaves
* Execute command "minimalist-terminal:open-terminal"
* Execute command "minimalist-terminal:open-terminal"
* Workspace has exactly "1" leaf of type "minimalist-terminal-view"
