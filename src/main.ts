import * as path from "path";
import { Plugin, WorkspaceLeaf } from "obsidian";
import {
  TerminalView,
  VIEW_TYPE_TERMINAL,
  MAX_TERMINALS,
  resetTerminalCounter,
  setTerminalShell,
} from "./TerminalView";
import { PtyBridge } from "./PtyBridge";
import { TerminalSettingsTab } from "./SettingsTab";
import {
  type TerminalSettings,
  DEFAULT_SETTINGS,
  detectShells,
  resolveShell,
} from "./settings";

export default class TerminalPlugin extends Plugin {
  settings!: TerminalSettings;

  async onload() {
    // Tell PtyBridge where the plugin is installed so it can find node-pty.
    const basePath: string = (this.app.vault.adapter as any).basePath || "";
    PtyBridge.pluginDir = path.join(
      basePath,
      ".obsidian",
      "plugins",
      this.manifest.id,
    );

    await this.loadSettings();

    // Resolve shell once so every terminal uses the same setting.
    // If the user changes the setting, they need to open a new terminal.
    this.syncTerminalShell();

    this.registerView(VIEW_TYPE_TERMINAL, (leaf) => new TerminalView(leaf));

    this.addRibbonIcon("terminal", "Open terminal", () => {
      this.syncTerminalShell();
      this.openTerminal();
    });

    this.addCommand({
      id: "open-terminal",
      name: "Open terminal",
      callback: () => {
        this.syncTerminalShell();
        this.openTerminal();
      },
    });

    this.addSettingTab(new TerminalSettingsTab(this.app, this));
  }

  onunload() {
    this.app.workspace.detachLeavesOfType(VIEW_TYPE_TERMINAL);
  }

  async loadSettings(): Promise<void> {
    this.settings = Object.assign(
      {},
      DEFAULT_SETTINGS,
      await this.loadData(),
    );
  }

  async saveSettings(): Promise<void> {
    await this.saveData(this.settings);
  }

  /** Resolve the configured shell and set the TerminalView's static path. */
  private syncTerminalShell(): void {
    const detected = detectShells();
    setTerminalShell(resolveShell(this.settings.shell, detected));
  }

  /** Open a new terminal tab in the bottom pane. */
  private async openTerminal(): Promise<void> {
    const { workspace } = this.app;

    const existing = workspace.getLeavesOfType(VIEW_TYPE_TERMINAL);
    if (existing.length >= MAX_TERMINALS) {
      workspace.revealLeaf(existing[existing.length - 1]);
      return;
    }

    let leaf: WorkspaceLeaf;
    if (existing.length > 0) {
      const parent = existing[0].parent;
      const tabCount = (parent as any).children?.length ?? existing.length;
      leaf = workspace.createLeafInParent(parent, tabCount);
    } else {
      resetTerminalCounter();
      leaf = workspace.getLeaf("split", "horizontal");
    }
    await leaf.setViewState({ type: VIEW_TYPE_TERMINAL, active: true });
    workspace.revealLeaf(leaf);
  }
}
