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

    // Container div
    this.container = contentEl.createDiv("terminal-container");

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

    // Fit after a tick so xterm has dimensions
    setTimeout(() => this.fitAddon.fit(), 10);

    // Spawn PTY — dimensions are 0 until fit, so use defaults
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

    // User input → PTY (with keyboard filtering applied at xterm level)
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
        return false; // don't pass to PTY
      }
      if (e.ctrlKey && e.shiftKey && e.key === "V") {
        navigator.clipboard.readText().then((text: string) => {
          this.pty?.write(text);
        });
        return false;
      }
      return true; // everything else (Ctrl+C, Ctrl+V, etc.) → PTY
    });

    // Right-click paste
    this.term.element?.addEventListener("contextmenu", (e: MouseEvent) => {
      e.preventDefault();
      navigator.clipboard.readText().then((text: string) => {
        this.pty?.write(text);
      });
    });

    // Resize: container size changes → fit xterm → resize PTY
    this.resizeObserver = new ResizeObserver(() => {
      this.fitAddon.fit();
      if (this.pty) {
        this.pty.resize(this.term.cols, this.term.rows);
      }
    });
    this.resizeObserver.observe(this.container);

    // Focus terminal on open
    this.term.focus();
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
