# Open Terminal

Проверка открытия терминала: по иконке (ribbon) и через Command Palette.

## Открытие через Command Palette

tags: mvp, doD-2, cdp

* Закрыть все листья терминала
* Выполнить команду "obsidian-terminal:open-terminal"
* В workspace есть лист с типом "obsidian-terminal-view"
* DOM содержит элемент с классом "xterm"

## Повторное открытие не дублирует

tags: mvp, doD-2, cdp

* Закрыть все листья терминала
* Выполнить команду "obsidian-terminal:open-terminal"
* Выполнить команду "obsidian-terminal:open-terminal"
* В workspace ровно 1 лист с типом "obsidian-terminal-view"
