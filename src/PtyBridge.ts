/** Thin wrapper over node-pty. Spawns a shell, pipes data in/out. */
export class PtyBridge {
  private pty: unknown = null;
  private writeFn: ((data: string) => void) | null = null;
  private resizeFn: ((cols: number, rows: number) => void) | null = null;
  private killFn: (() => void) | null = null;

  constructor(
    private callbacks: PtyBridgeCallbacks,
    cols: number,
    rows: number,
  ) {
    // Lazy require — node-pty is a native module, may not be available
    // if the platform binary is missing or ABI-mismatched.
    let spawn: Function;
    try {
      const ptyModule = require("@lydell/node-pty");
      spawn = ptyModule.spawn;
    } catch (e) {
      this.callbacks.onData(
        `\r\n\x1b[31m[Terminal unavailable]\x1b[0m\r\n` +
          `Could not load node-pty native module.\r\n` +
          `Run: npm install @lydell/node-pty-darwin-arm64\r\n` +
          `Error: ${(e as Error).message}\r\n\r\n`,
      );
      this.callbacks.onExit(-1);
      return;
    }

    const shell = process.env.SHELL || "bash";
    const cwd = process.env.HOME || process.env.USERPROFILE || "/";

    try {
      const pty = spawn(shell, [], {
        name: "xterm-256color",
        cols,
        rows,
        cwd,
        env: process.env as { [key: string]: string },
      });

      pty.onData((data: string) => {
        this.callbacks.onData(data);
      });

      pty.onExit(
        ({ exitCode }: { exitCode: number; signal?: number }) => {
          this.callbacks.onExit(exitCode);
          this.destroy();
        },
      );

      this.pty = pty;
      this.writeFn = (data: string) => pty.write(data);
      this.resizeFn = (c: number, r: number) => pty.resize(c, r);
      this.killFn = () => {
        try { pty.kill(); } catch { /* ignore */ }
      };
    } catch (e) {
      this.callbacks.onData(
        `\r\n\x1b[31m[Failed to spawn shell]\x1b[0m\r\n` +
          `Error: ${(e as Error).message}\r\n\r\n`,
      );
      this.callbacks.onExit(-1);
    }
  }

  write(data: string): void {
    this.writeFn?.(data);
  }

  resize(cols: number, rows: number): void {
    this.resizeFn?.(cols, rows);
  }

  kill(): void {
    this.killFn?.();
    this.destroy();
  }

  private destroy(): void {
    this.writeFn = null;
    this.resizeFn = null;
    this.killFn = null;
    this.pty = null;
  }
}

export interface PtyBridgeCallbacks {
  onData: (data: string) => void;
  onExit: (exitCode: number) => void;
}
