import { App, PluginSettingTab, Setting } from "obsidian";
import type TerminalPlugin from "./main";
import { detectShells, type ShellEntry } from "./settings";

export class TerminalSettingsTab extends PluginSettingTab {
  private plugin: TerminalPlugin;
  private shells: ShellEntry[] = [];
  /**
   * Sticky flag: set to true when user picks "Custom path…" in dropdown.
   * Survives re-renders so the custom input stays visible while the user types.
   * Reset to false only when the user picks a detected shell from the dropdown.
   */
  private customMode = false;

  constructor(app: App, plugin: TerminalPlugin) {
    super(app, plugin);
    this.plugin = plugin;
  }

  display(): void {
    const { containerEl } = this;
    containerEl.empty();

    this.shells = detectShells();

    // Custom mode is sticky: once the user picks "Custom path…" it stays
    // until they pick a detected shell. Also auto-detect from saved setting.
    const shellIsCustom =
      this.plugin.settings.shell !== "" &&
      !this.shells.some((s) => s.path === this.plugin.settings.shell);
    const useCustom = this.customMode || shellIsCustom;

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
        if (useCustom) {
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
            this.customMode = true;
            // Keep previous shell value (if any) so the user can edit it
          } else {
            this.customMode = false;
            this.plugin.settings.shell = value;
          }
          await this.plugin.saveSettings();
          this.display();
        });
      });

    // Warning for selected shell
    const selectedPath = useCustom
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

    if (useCustom) {
      new Setting(containerEl)
        .setName("Custom shell path")
        .setDesc("Absolute path to a shell executable.")
        .addText((text) => {
          text
            .setPlaceholder("/opt/homebrew/bin/fish")
            .setValue(this.plugin.settings.shell)
            .onChange(async (value) => {
              this.plugin.settings.shell = value.trim();
              await this.plugin.saveSettings();
              // Inline validation only — NO full re-render (would steal focus)
              const current = this.plugin.settings.shell.trim();
              if (current) {
                this.validateAndShow(text.inputEl, current);
              } else {
                text.inputEl.style.borderColor = "";
                text.inputEl.title = "";
              }
            });

          // Initial validation
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
