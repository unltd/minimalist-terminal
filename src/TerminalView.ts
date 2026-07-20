import { ItemView, WorkspaceLeaf } from "obsidian";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { PtyBridge } from "./PtyBridge";

export const VIEW_TYPE_TERMINAL = "obsidian-terminal-view";

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

    if (this.container) return;

    contentEl.empty();
    contentEl.classList.add("terminal-view-content");

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
      rows: 24,
      cols: 80,
      scrollback: 1000,
      allowProposedApi: true,
    });

    this.fitAddon = new FitAddon();
    this.term.loadAddon(this.fitAddon);

    this.term.open(this.container);
    this.scheduleFit(0);

    const vaultPath = (this.app.vault.adapter as any).basePath || process.env.HOME || "/";
    this.pty = new PtyBridge(
      {
        onData: (data: string) => this.term!.write(data),
        onExit: () => {
          this.app.workspace.detachLeavesOfType(VIEW_TYPE_TERMINAL);
        },
      },
      this.term.cols,
      this.term.rows,
      vaultPath,
    );

    this.term.onData((data: string) => {
      this.pty?.write(data);
    });

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
      e.stopPropagation();
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

    // Focus the terminal. Obsidian steals focus after view open;
    // we fight back with a capture-phase mousedown (any click in
    // terminal gives focus) and a retry loop for initial focus.
    this.container?.addEventListener("mousedown", () => {
      this.term?.focus();
    }, { capture: true, passive: true });

    let focusTries = 0;
    const maxFocusTries = 60; // 3 seconds
    const tryFocus = () => {
      if (focusTries >= maxFocusTries || !this.term) return;
      focusTries++;
      this.term?.focus();
      setTimeout(tryFocus, 50);
    };
    setTimeout(tryFocus, 50);
  }

  private scheduleFit(attempt: number): void {
    if (!this.container || !this.fitAddon || !this.term) return;
    const rect = this.container.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0) {
      this.fitAddon.fit();
      if (this.pty) {
        this.pty.resize(this.term.cols, this.term.rows);
      }
      // Terminal is ready — take focus
      this.term.focus();
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
    this.container?.remove();
    this.container = null;
  }
}
