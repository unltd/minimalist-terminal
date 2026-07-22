import { Plugin, WorkspaceLeaf } from "obsidian";
import { TerminalView, VIEW_TYPE_TERMINAL, MAX_TERMINALS, resetTerminalCounter } from "./TerminalView";

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

  /** Open a new terminal tab in the bottom pane. Always creates a new leaf. */
  private async openTerminal(): Promise<void> {
    const { workspace } = this.app;

    const existing = workspace.getLeavesOfType(VIEW_TYPE_TERMINAL);
    if (existing.length >= MAX_TERMINALS) {
      // Focus the most recently used terminal instead of creating another
      workspace.revealLeaf(existing[existing.length - 1]);
      return;
    }

    let leaf: WorkspaceLeaf;
    if (existing.length > 0) {
      // Create a new tab next to existing terminals
      const parent = existing[0].parent;
      const tabCount = (parent as any).children?.length ?? existing.length;
      leaf = workspace.createLeafInParent(parent, tabCount);
    } else {
      // First terminal after all were closed: restart numbering
      resetTerminalCounter();
      leaf = workspace.getLeaf("split", "horizontal");
    }
    await leaf.setViewState({ type: VIEW_TYPE_TERMINAL, active: true });
    workspace.revealLeaf(leaf);
  }
}
