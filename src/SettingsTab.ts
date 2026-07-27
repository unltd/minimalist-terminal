import { App, PluginSettingTab, Setting } from "obsidian";
import type TerminalPlugin from "./main";
import { detectShells, type ShellEntry } from "./settings";

export class TerminalSettingsTab extends PluginSettingTab {
  private plugin: TerminalPlugin;
  private shells: ShellEntry[] = [];
  private useCustom = false;

  constructor(app: App, plugin: TerminalPlugin) {
    super(app, plugin);
    this.plugin = plugin;
  }

  display(): void {
    const { containerEl } = this;
    containerEl.empty();

    this.shells = detectShells();
    this.useCustom = this.isCustomPath(this.plugin.settings.shell);

    // ── Shell selection ──────────────────────────────────────────

    new Setting(containerEl)
      .setName("Shell")
      .setDesc("The shell spawned in new terminals. Changes apply to terminals opened after saving.")
      .addDropdown((dropdown) => {
        // Detected shells
        for (const s of this.shells) {
          dropdown.addOption(s.path, s.label);
        }

        // Custom option
        dropdown.addOption("__custom__", "Custom path…");

        // Select current value
        if (this.useCustom) {
          dropdown.setValue("__custom__");
        } else if (
          this.plugin.settings.shell &&
          this.shells.some((s) => s.path === this.plugin.settings.shell)
        ) {
          dropdown.setValue(this.plugin.settings.shell);
        } else if (this.shells.length > 0) {
          // Default: first detected (zsh)
          dropdown.setValue(this.shells[0].path);
        }

        dropdown.onChange(async (value) => {
          if (value === "__custom__") {
            this.useCustom = true;
            this.plugin.settings.shell = "";
          } else {
            this.useCustom = false;
            this.plugin.settings.shell = value;
          }
          await this.plugin.saveSettings();
          // Re-render to show/hide custom input + warning
          this.display();
        });
      });

    // Warning for selected shell
    const selectedPath = this.useCustom
      ? this.plugin.settings.shell
      : this.plugin.settings.shell || this.shells[0]?.path;
    const selectedShell = this.shells.find((s) => s.path === selectedPath);
    if (selectedShell?.warning) {
      containerEl.createEl("div", {
        text: `⚠️ ${selectedShell.warning}`,
        cls: "setting-item-description",
        attr: { style: "color: #e6b422; margin: -8px 0 12px 0;" },
      } as any);
    }

    // ── Custom path input ────────────────────────────────────────

    if (this.useCustom) {
      const customSetting = new Setting(containerEl)
        .setName("Custom shell path")
        .setDesc("Absolute path to a shell executable.")
        .addText((text) => {
          text
            .setPlaceholder("/opt/homebrew/bin/fish")
            .setValue(this.plugin.settings.shell)
            .onChange(async (value) => {
              this.plugin.settings.shell = value.trim();
              await this.plugin.saveSettings();
              // Re-render to update validation state
              this.display();
            });

          // Validation
          const current = this.plugin.settings.shell.trim();
          if (current) {
            this.validateAndShow(text.inputEl, current);
          }
          return text;
        });
    }

    // ── Detected shells info ─────────────────────────────────────

    if (this.shells.length === 0) {
      containerEl.createEl("div", {
        text: "No shells detected. Please enter a custom path above.",
        cls: "setting-item-description",
        attr: { style: "color: #e06c75; margin-top: 8px;" },
      } as any);
    }
  }

  /** Check whether the current setting is a path not in the detected list. */
  private isCustomPath(shell: string): boolean {
    if (!shell) return false;
    return !this.shells.some((s) => s.path === shell);
  }

  /** Live validation: check that the path exists and is executable. */
  private validateAndShow(inputEl: HTMLInputElement, shellPath: string): void {
    const fs = require("fs") as typeof import("fs");

    let ok = true;
    let msg = "";

    try {
      const stat = fs.statSync(shellPath);
      if (!stat.isFile()) {
        ok = false;
        msg = "Not a file";
      } else {
        fs.accessSync(shellPath, fs.constants.X_OK);
        msg = "Valid shell ✓";
      }
    } catch {
      ok = false;
      msg = "File not found or not accessible";
    }

    inputEl.style.borderColor = ok ? "#4caf50" : "#e06c75";
    inputEl.title = msg;
  }
}
