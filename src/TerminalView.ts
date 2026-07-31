import { ItemView, WorkspaceLeaf } from "obsidian";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { PtyBridge } from "./PtyBridge";

export const VIEW_TYPE_TERMINAL = "obsidian-terminal-view";

/** Shell path, set by the plugin from user settings before opening views. */
export let terminalShell: string = "";

export function setTerminalShell(s: string): void {
  terminalShell = s;
}

let nextTerminal = 1;

export function resetTerminalCounter(): void {
  nextTerminal = 1;
}

export class TerminalView extends ItemView {
  private readonly terminalNumber: number;
  private term: Terminal | null = null;
  private fitAddon: FitAddon | null = null;
  private pty: PtyBridge | null = null;
  private container: HTMLElement | null = null;
  private resizeObserver: ResizeObserver | null = null;

  constructor(leaf: WorkspaceLeaf) {
    super(leaf);
    this.terminalNumber = nextTerminal++;
  }

  getViewType(): string {
    return VIEW_TYPE_TERMINAL;
  }

  getDisplayText(): string {
    return `Terminal ${this.terminalNumber}`;
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
          // Don't detach — keep the terminal visible with the error/output.
          // PtyBridge writes an error message via onData before calling onExit
          // when initialization fails (e.g. missing node-pty on Windows).
          if (this.term) {
            this.term.write("\r\n[shell exited]\r\n");
          }
        },
      },
      this.term.cols,
      this.term.rows,
      vaultPath,
      terminalShell || process.env.SHELL || "bash",
    );

    // PtyBridge constructor may fail synchronously on platforms without node-pty
    // (e.g. Windows). If it calls onExit → leaf.detach() → onClose() → term=null,
    // we must bail out before accessing this.term.
    if (!this.term) return;

    this.term.onData((data: string) => {
      this.pty?.write(data);
    });

    const copySelection = () => {
      const selection = this.term!.getSelection();
      if (selection) {
        navigator.clipboard.writeText(selection).catch(() => {
          // navigator.clipboard may fail on some platforms;
          // the selection remains in xterm.js for manual copy.
        });
      }
    };

    const pasteClipboard = () => {
      navigator.clipboard.readText().then((text: string) => {
        this.pty?.write(text);
      }).catch(() => { /* clipboard read denied */ });
    };

    this.term.attachCustomKeyEventHandler((e: KeyboardEvent): boolean => {
      // Ctrl+Shift+C → copy (macOS standard)
      if (e.ctrlKey && e.shiftKey && e.key === "C") {
        copySelection();
        return false;
      }
      // Ctrl+C with selection → copy.
      // Without selection → SIGINT (ETX).
      if (!e.shiftKey && e.ctrlKey && e.key === "c") {
        const sel = this.term!.getSelection();
        if (sel) {
          copySelection();
        } else {
          this.pty?.write("\x03");
        }
        return false;
      }
      // Ctrl+V → return false to prevent xterm.js from calling
      // preventDefault() on the keydown.  If xterm.js prevented
      // the default, the browser would NOT generate the paste
      // event and our paste guard below would never fire.
      // The actual paste happens in the textarea guard.
      if (!e.shiftKey && e.ctrlKey && e.key === "v") {
        return false;
      }
      return true;
    });

    // Block xterm.js native copy event.
    this.term.element?.addEventListener("copy", (e: ClipboardEvent) => {
      e.preventDefault();
    });

    // Handle paste synchronously from ClipboardEvent. Single code
    // path — xterm.js never sees the event (stopImmediatePropagation).
    const textarea = this.term.element?.querySelector("textarea");
    if (textarea) {
      textarea.addEventListener("paste", (e: ClipboardEvent) => {
        const text = e.clipboardData?.getData("text/plain");
        if (text) {
          this.pty?.write(text);
        }
        e.preventDefault();
        e.stopImmediatePropagation();
      }, { capture: true });
    }

    this.term.element?.addEventListener("contextmenu", (e: MouseEvent) => {
      e.preventDefault();
      e.stopPropagation();
      navigator.clipboard.readText().then((text: string) => {
        this.pty?.write(text);
      });
    });

    this.resizeObserver = new ResizeObserver(() => {
      if (!this.fitAddon || !this.pty || !this.container) return;
      const rect = this.container.getBoundingClientRect();
      // Skip if container has no dimensions yet — scheduleFit handles initial sizing
      if (rect.width === 0 || rect.height === 0) return;
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
