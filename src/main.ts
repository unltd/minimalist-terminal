import { Plugin } from "obsidian";
import { TerminalView, VIEW_TYPE_TERMINAL } from "./TerminalView";

export default class TerminalPlugin extends Plugin {
  async onload() {
    this.registerView(VIEW_TYPE_TERMINAL, (leaf) => new TerminalView(leaf));

    this.addRibbonIcon("terminal", "Open terminal", () => {
      this.openTerminal();
    });

    this.addCommand({
      id: "open-terminal",
      name: "Open terminal",
      callback: () => this.openTerminal(),
    });
  }

  onunload() {
    this.app.workspace.detachLeavesOfType(VIEW_TYPE_TERMINAL);
  }

  /** Open terminal in a bottom pane. If one exists, reveal it instead. */
  private async openTerminal(): Promise<void> {
    const { workspace } = this.app;

    let leaf = workspace.getLeavesOfType(VIEW_TYPE_TERMINAL)[0];
    if (!leaf) {
      leaf = workspace.getLeaf("split", "horizontal");
      await leaf.setViewState({ type: VIEW_TYPE_TERMINAL, active: true });
    }
    workspace.revealLeaf(leaf);
  }
}
