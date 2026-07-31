import * as path from "path";
import { Plugin, WorkspaceLeaf, addIcon } from "obsidian";
import {
  TerminalView,
  VIEW_TYPE_TERMINAL,
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

    // Custom macOS Terminal-style icon.
    // Follows Lucide conventions (viewBox 0 0 24 24, stroke-width 2) so it
    // blends with Obsidian's built-in icons. Rounded window frame + >_ prompt
    // distinguishes it from the command palette.
    addIcon(
      "terminal-mac",
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
        fill="none" stroke="currentColor" stroke-width="2"
        stroke-linecap="round" stroke-linejoin="round">
        <rect x="3" y="4" width="18" height="16" rx="2"/>
        <polyline points="8 15 12 11 8 7"/>
        <line x1="13" y1="17" x2="18" y2="17"/>
      </svg>`,
    );

    await this.loadSettings();

    // Resolve shell once so every terminal uses the same setting.
    // If the user changes the setting, they need to open a new terminal.
    this.syncTerminalShell();

    this.registerView(VIEW_TYPE_TERMINAL, (leaf) => new TerminalView(leaf));

    this.addRibbonIcon("terminal-mac", "Open terminal", () => {
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
