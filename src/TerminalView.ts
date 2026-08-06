import { ItemView, WorkspaceLeaf } from "obsidian";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { PtyBridge } from "./PtyBridge";

export const VIEW_TYPE_TERMINAL = "minimalist-terminal-view";

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
        onExit: (exitCode) => {
          // Init failure (exitCode < 0, e.g. missing node-pty) — keep the
          // terminal visible so the error message written via onData stays
          // readable. Normal shell exit (exitCode >= 0) closes the pane.
          if (exitCode < 0) {
            if (this.term) {
              this.term.write("\r\n[shell exited]\r\n");
            }
            return;
          }
          this.leaf.detach();
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

    // OSC 52 clipboard support. Terminal programs (tmux, Neovim, etc.)
    // send OSC 52 escape sequences to write to the system clipboard.
    // Format: OSC 52 ; Pc ; <base64-data> ST
    // Pc = 'c' for system clipboard (what we want).
    // This is the only reliable clipboard channel from a remote/VPS
    // tmux to the local macOS clipboard — pbcopy doesn't exist on Linux.
    this.term.parser.registerOscHandler(52, (data: string): boolean => {
      // data is the payload between OSC 52 ; and ST, e.g. "c;<base64>"
      const colonIdx = data.indexOf(";");
      if (colonIdx === -1) return false;

      const selector = data.slice(0, colonIdx);
      // Only handle system clipboard ('c') and unspecific (empty)
      if (selector !== "c" && selector !== "") return false;

      const b64 = data.slice(colonIdx + 1);
      if (!b64) return false;

      try {
        const text = atob(b64);
        navigator.clipboard.writeText(text).catch(() => {
          // OSC 52 is fire-and-forget — no ACK to terminal program
        });
      } catch {
        // Invalid base64 — ignore
      }
      return true; // Handled
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
      // Ctrl+Shift+C → copy.
      // This shortcut does NOT trigger a browser "copy" event,
      // so we write to clipboard directly via the async API.
      if (e.ctrlKey && e.shiftKey && e.key === "C") {
        copySelection();
        return false;
      }
      // Ctrl+C with selection → copy (let browser fire "copy" event).
      // Ctrl+C without selection → SIGINT (ETX).
      if (!e.shiftKey && e.ctrlKey && e.key === "c") {
        if (!this.term!.getSelection()) {
          this.pty?.write("\x03");
        }
        // Either way, return false. With selection the browser
        // fires a "copy" event and our handler below sets the
        // clipboard synchronously via e.clipboardData.
        return false;
      }
      // Cmd+C (macOS standard copy). Let the browser fire
      // "copy" event → our handler below sets clipboard.
      if (e.metaKey && !e.shiftKey && e.key === "c") {
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

    // Handle copy event — write xterm.js selection to clipboard.
    // Catches Ctrl+C (selection), Cmd+C, Edit→Copy, and any other
    // browser-initiated copy action. Uses the synchronous
    // e.clipboardData API which is more reliable in Electron than
    // navigator.clipboard.writeText().
    this.term.element?.addEventListener("copy", (e: ClipboardEvent) => {
      const selection = this.term!.getSelection();
      if (selection) {
        e.clipboardData?.setData("text/plain", selection);
      }
      e.preventDefault(); // Use our data, not the browser's DOM selection
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
