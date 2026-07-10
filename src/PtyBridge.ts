import { spawn, IPty } from "@lydell/node-pty";

export interface PtyBridgeCallbacks {
  onData: (data: string) => void;
  onExit: (exitCode: number) => void;
}

/** Thin wrapper over node-pty. Spawns a shell, pipes data in/out. */
export class PtyBridge {
  private pty: IPty | null = null;

  constructor(
    private callbacks: PtyBridgeCallbacks,
    cols: number,
    rows: number,
  ) {
    const shell = process.env.SHELL || "bash";
    const cwd = process.env.HOME || process.env.USERPROFILE || "/";

    this.pty = spawn(shell, [], {
      name: "xterm-256color",
      cols,
      rows,
      cwd,
      env: process.env as { [key: string]: string },
    });

    this.pty.onData((data: string) => {
      this.callbacks.onData(data);
    });

    this.pty.onExit(({ exitCode }: { exitCode: number; signal?: number }) => {
      this.callbacks.onExit(exitCode);
      this.pty = null;
    });
  }

  write(data: string): void {
    this.pty?.write(data);
  }

  resize(cols: number, rows: number): void {
    this.pty?.resize(cols, rows);
  }

  /** Kill the shell process. Safe to call multiple times. */
  kill(): void {
    if (this.pty) {
      this.pty.kill();
      this.pty = null;
    }
  }
}
