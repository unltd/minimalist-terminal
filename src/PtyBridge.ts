import * as path from "path";
import * as fs from "fs";

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
    cwd: string,
  ) {
    let spawn: Function;

    try {
      // Electron renderer resolves modules from inside Obsidian.app,
      // not from our plugin directory. We must use an absolute path.
      const ptyPath = PtyBridge.findNodePty();
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const ptyModule = require(ptyPath);
      spawn = ptyModule.spawn;
    } catch (e) {
      this.callbacks.onData(
        `\r\n\x1b[31m[Terminal unavailable]\x1b[0m\r\n` +
          `node-pty not found.\r\n` +
          `Install: npm install @lydell/node-pty-darwin-arm64\r\n` +
          `Error: ${(e as Error).message}\r\n\r\n`,
      );
      this.callbacks.onExit(-1);
      return;
    }

    const shell = process.env.SHELL || "bash";

    try {
      // -l (login) + -i (interactive): sources .bash_profile AND .bashrc so PATH is complete
      const pty = spawn(shell, ["-l", "-i"], {
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

  /** Find node-pty by scanning known locations. */
  private static findNodePty(): string {
    const candidates = [
      // Project root (same path inside container and on host)
      "/Users/pavel/IdeaProjects/obsidian-terminal/node_modules/@lydell/node-pty",
      // Vault plugin dir
      "/Users/pavel/obsidian-test/.obsidian/plugins/obsidian-terminal/node_modules/@lydell/node-pty",
      // Relative to cwd
      path.join(process.cwd(), "node_modules/@lydell/node-pty"),
    ];

    for (const p of candidates) {
      const indexPath = path.join(p, "index.js");
      if (fs.existsSync(indexPath)) {
        return p;
      }
    }

    // Not found — let require throw with a useful error
    return "@lydell/node-pty";
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
