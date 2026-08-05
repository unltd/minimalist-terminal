# Text Selection

Verifies mouse text selection in the terminal.

## Programmatic selection returns text
tags: mvp, doD-4, cdp

* Open terminal
* Wait for shell prompt within "8" seconds
* Enter command "echo selection_test_line"
* Terminal contains text in buffer
* Programmatic selection via term.selectLines returns non-empty text

## Selection elements unaffected by Obsidian CSS
tags: mvp, doD-4, cdp

* Open terminal
* Wait for shell prompt within "8" seconds
* CSS position of element ".xterm-screen" equals "relative"
* DOM contains selector ".xterm-selection-layer"
