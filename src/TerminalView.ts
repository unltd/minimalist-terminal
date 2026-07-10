import { ItemView, WorkspaceLeaf } from "obsidian";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebglAddon } from "@xterm/addon-webgl";
import { PtyBridge } from "./PtyBridge";

export const VIEW_TYPE_TERMINAL = "obsidian-terminal-view";

export class TerminalView extends ItemView {
  private term: Terminal;
  private fitAddon: FitAddon;
  private pty: PtyBridge | null = null;
  private container: HTMLElement | null = null;
  private resizeObserver: ResizeObserver | null = null;

  constructor(leaf: WorkspaceLeaf) {
    super(leaf);
  }

  getViewType(): string {
    return VIEW_TYPE_TERMINAL;
  }

  getDisplayText(): string {
    return "Terminal";
  }

  getIcon(): string {
    return "terminal";
  }

  async onOpen(): Promise<void> {
    const { contentEl } = this;

    // Reset content styles — absolute fill within the view
    contentEl.style.cssText = "position: relative; width: 100%; height: 100%; overflow: hidden;";
    contentEl.empty();

    // Container fills contentEl absolutely
    this.container = contentEl.createDiv("terminal-container");
    this.container.style.cssText =
      "position: absolute; top: 0; left: 0; right: 0; bottom: 0; overflow: hidden;";

    // Terminal emulator
    this.term = new Terminal({
      cursorBlink: true,
      cursorStyle: "bar",
      fontSize: 13,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      theme: {
        background: getComputedStyle(document.body)
          .getPropertyValue("--background-primary")
          .trim() || "#1e1e1e",
        foreground: getComputedStyle(document.body)
          .getPropertyValue("--text-normal")
          .trim() || "#d4d4d4",
        cursor: "#d4d4d4",
        selectionBackground: "#264f78",
      },
      allowProposedApi: true,
    });

    // Addons
    this.fitAddon = new FitAddon();
    this.term.loadAddon(this.fitAddon);

    try {
      this.term.loadAddon(new WebglAddon());
    } catch {
      // Fallback to canvas renderer if WebGL unavailable
    }

    // Mount
    this.term.open(this.container);

    // Fit after layout settles, with retries
    this.fitTerminal();

    // Spawn PTY after first fit
    this.pty = new PtyBridge(
      {
        onData: (data: string) => this.term.write(data),
        onExit: (code: number) => {
          this.term.write(`\r\n[Process exited with code ${code}]\r\n`);
        },
      },
      this.term.cols,
      this.term.rows,
    );

    // User input → PTY
    this.term.onData((data: string) => {
      this.pty?.write(data);
    });

    // Clipboard handling: Ctrl+Shift+C copy, Ctrl+Shift+V paste
    this.term.attachCustomKeyEventHandler((e: KeyboardEvent): boolean => {
      if (e.ctrlKey && e.shiftKey && e.key === "C") {
        const selection = this.term.getSelection();
        if (selection) {
          navigator.clipboard.writeText(selection);
        }
        return false;
      }
      if (e.ctrlKey && e.shiftKey && e.key === "V") {
        navigator.clipboard.readText().then((text: string) => {
          this.pty?.write(text);
        });
        return false;
      }
      return true; // Ctrl+C, Ctrl+V etc → PTY
    });

    // Right-click paste
    this.term.element?.addEventListener("contextmenu", (e: MouseEvent) => {
      e.preventDefault();
      navigator.clipboard.readText().then((text: string) => {
        this.pty?.write(text);
      });
    });

    // Resize: container size changes → fit xterm → resize PTY
    this.resizeObserver = new ResizeObserver((entries) => {
      // Small delay — let DOM settle after pane resize
      requestAnimationFrame(() => {
        this.fitAddon.fit();
        if (this.pty) {
          this.pty.resize(this.term.cols, this.term.rows);
        }
      });
    });
    this.resizeObserver.observe(this.container);

    // Focus terminal
    this.term.focus();
  }

  /** Fit the terminal with retries — Obsidian may not have laid out the pane yet. */
  private fitTerminal(attempt = 0): void {
    if (!this.container) return;

    const rect = this.container.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0) {
      this.fitAddon.fit();
      if (this.pty) {
        this.pty.resize(this.term.cols, this.term.rows);
      }
    } else if (attempt < 10) {
      // Container has no dimensions yet — retry
      setTimeout(() => this.fitTerminal(attempt + 1), 50);
    }
  }

  async onClose(): Promise<void> {
    this.resizeObserver?.disconnect();
    this.resizeObserver = null;
    this.pty?.kill();
    this.pty = null;
    this.term.dispose();
    this.container = null;
  }
}
