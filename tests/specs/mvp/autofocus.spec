# Autofocus

Verifies that the terminal auto-focuses on open.

## Focus after opening
tags: mvp, doD-6, cdp

* Close all terminal leaves
* Open terminal
* Within "5" seconds the terminal gains focus
* Active element is a textarea inside xterm

## Clicking in the terminal gives focus
tags: mvp, doD-6, cdp

* Open terminal
* Wait for shell prompt within "8" seconds
* Click the terminal container
* Active element is a textarea inside xterm
