import { Plugin, Notice } from "obsidian";

export default class TerminalPlugin extends Plugin {
  async onload() {
    new Notice("Terminal plugin loaded");

    this.addRibbonIcon("terminal", "Open terminal", () => {
      new Notice("Terminal — coming soon");
    });

    this.addCommand({
      id: "open-terminal",
      name: "Open terminal",
      callback: () => {
        new Notice("Terminal — coming soon");
      },
    });
  }

  onunload() {}
}
