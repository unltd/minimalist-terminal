# Scroll

Verifies scrolling in the terminal.

## Scroll after buffer fills up
tags: mvp, doD-5, cdp

* Open terminal
* Wait for shell prompt within "8" seconds
* Enter command to generate "100" lines of output
* Terminal viewport has non-zero scrollTop

## Scrollback preserves lines
tags: mvp, doD-5, cdp

* Open terminal
* Wait for shell prompt within "8" seconds
* Enter command to generate "50" lines of output
* Terminal buffer length is greater than "0"
* Terminal buffer length is at least "50"
