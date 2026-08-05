# Close on Ctrl+D — No Zombies

Verifies that closing the terminal with Ctrl+D (exit) leaves no zombie processes.

## Close via Ctrl+D
tags: mvp, doD-7, cdp

* Open terminal
* Wait for shell prompt within "8" seconds
* Send command "exit" to terminal with newline
* Within "8" seconds the terminal leaf is removed from workspace
* No node-pty processes in the system

## Close leaf via Obsidian API
tags: mvp, doD-7, cdp

* Open terminal
* Wait for shell prompt within "8" seconds
* Close all terminal leaves via workspace API
* Within "5" seconds the terminal leaf is removed from workspace
* No node-pty processes in the system
