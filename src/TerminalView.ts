import { ItemView, WorkspaceLeaf } from "obsidian";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { PtyBridge } from "./PtyBridge";

export const VIEW_TYPE_TERMINAL = "obsidian-terminal-view";
const VERSION = "0.1.4";

export class TerminalView extends ItemView {
  private term: Terminal | null = null;
  private fitAddon: FitAddon | null = null;
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

    contentEl.empty();
    contentEl.classList.add("terminal-view-content");

    // Debug badge — rendered in DOM, always visible
    const badge = contentEl.createDiv("terminal-debug");
    badge.setText(`v${VERSION} | waiting for fit...`);

    this.container = contentEl.createDiv("terminal-container");

    this.term = new Terminal({
      cursorBlink: true,
      cursorStyle: "bar",
      fontSize: 13,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      theme: {
        background: "#1e1e1e",
        foreground: "#d4d4d4",
        cursor: "#d4d4d4",
        selectionBackground: "#264f78",
      },
      // Start with explicit rows so xterm has size before first fit
      rows: 24,
      cols: 80,
      allowProposedApi: true,
    });

    this.fitAddon = new FitAddon();
    this.term.loadAddon(this.fitAddon);

    // Mount xterm
    this.term.open(this.container);

    // Test that xterm renders text
    this.term.writeln("Terminal v" + VERSION);

    // Fit after layout
    this.scheduleFit(0);

    // Spawn PTY
    this.pty = new PtyBridge(
      {
        onData: (data: string) => this.term!.write(data),
        onExit: (code: number) => {
          this.term!.write(`\r\n[exit ${code}]\r\n`);
        },
      },
      this.term.cols,
      this.term.rows,
    );

    this.term.onData((data: string) => {
      this.pty?.write(data);
    });

    // Clipboard
    this.term.attachCustomKeyEventHandler((e: KeyboardEvent): boolean => {
      if (e.ctrlKey && e.shiftKey && e.key === "C") {
        const selection = this.term!.getSelection();
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
      return true;
    });

    this.term.element?.addEventListener("contextmenu", (e: MouseEvent) => {
      e.preventDefault();
      navigator.clipboard.readText().then((text: string) => {
        this.pty?.write(text);
      });
    });

    this.resizeObserver = new ResizeObserver(() => {
      if (!this.fitAddon || !this.pty) return;
      this.fitAddon.fit();
      this.pty.resize(this.term!.cols, this.term!.rows);
    });
    this.resizeObserver.observe(this.container);

    this.term.focus();
  }

  private scheduleFit(attempt: number): void {
    if (!this.container || !this.fitAddon || !this.term) return;
    const rect = this.container.getBoundingClientRect();

    // Update debug badge
    const badge = this.contentEl.querySelector(".terminal-debug");
    if (badge) {
      badge.textContent = `v${VERSION} | rect=${Math.round(rect.width)}x${Math.round(rect.height)} | cols=${this.term.cols}x${this.term.rows} | attempt=${attempt}`;
    }

    if (rect.width > 0 && rect.height > 0) {
      this.fitAddon.fit();
      this.term.writeln(`[fit: ${this.term.cols}x${this.term.rows}]`);
      if (this.pty) {
        this.pty.resize(this.term.cols, this.term.rows);
      }
    } else if (attempt < 20) {
      setTimeout(() => this.scheduleFit(attempt + 1), 100);
    }
  }

  async onClose(): Promise<void> {
    this.resizeObserver?.disconnect();
    this.resizeObserver = null;
    this.pty?.kill();
    this.pty = null;
    this.term?.dispose();
    this.term = null;
    this.fitAddon = null;
    this.container = null;
  }
}
