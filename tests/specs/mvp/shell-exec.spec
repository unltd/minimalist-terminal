# Shell Execution

Verifies command execution in the terminal and output display.

## echo command
tags: mvp, doD-3, cdp

* Open terminal
* Wait for shell prompt within "8" seconds
* Enter command "echo hello_mvp_test"
* Within "5" seconds output contains "hello_mvp_test"

## pwd command
tags: mvp, doD-3, cdp

* Open terminal
* Wait for shell prompt within "8" seconds
* Enter command "pwd"
* Within "5" seconds output contains "pwd_separator"

## Prompt returns after command
tags: mvp, doD-3, cdp

* Open terminal
* Wait for shell prompt within "8" seconds
* Enter command "echo done"
* Within "5" seconds the terminal shows a new shell prompt
