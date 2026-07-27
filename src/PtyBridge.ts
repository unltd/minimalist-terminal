import * as path from "path";
import * as fs from "fs";
import { shellFlags } from "./settings";

/** Thin wrapper over node-pty. Spawns a shell, pipes data in/out. */
export class PtyBridge {
  /** Set by the plugin during onload to help find node-pty. */
  static pluginDir: string = "";

  private pty: unknown = null;
  private writeFn: ((data: string) => void) | null = null;
  private resizeFn: ((cols: number, rows: number) => void) | null = null;
  private killFn: (() => void) | null = null;

  constructor(
    private callbacks: PtyBridgeCallbacks,
    cols: number,
    rows: number,
    cwd: string,
    shell: string,
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

    // Verify the shell exists before spawning
    if (!fs.existsSync(shell)) {
      this.callbacks.onData(
        `\r\n\x1b[31m[Shell not found]\x1b[0m\r\n` +
          `${shell} does not exist.\r\n` +
          `Go to Settings → Community Plugins → Terminal → Options to select a different shell.\r\n\r\n`,
      );
      this.callbacks.onExit(-1);
      return;
    }

    const flags = shellFlags(shell);

    // Inherit parent env but override SHELL so tools that read $SHELL
    // (nvm, shell scripts, etc.) see the correct shell.
    const env = { ...(process.env as { [key: string]: string }) };
    env.SHELL = shell;

    try {
      const pty = spawn(shell, flags, {
        name: "xterm-256color",
        cols,
        rows,
        cwd,
        env,
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
          `Shell: ${shell} ${flags.join(" ")}\r\n` +
          `Error: ${(e as Error).message}\r\n\r\n`,
      );
      this.callbacks.onExit(-1);
    }
  }

  /** Find node-pty by scanning known locations. */
  private static findNodePty(): string {
    const candidates: string[] = [];

    // 1. Plugin's own node_modules — most reliable for installed plugins.
    //    The plugin sets PtyBridge.pluginDir to <vault>/.obsidian/plugins/<id>
    //    during onload; node-pty lives in its node_modules/.
    if (PtyBridge.pluginDir) {
      candidates.push(
        path.join(PtyBridge.pluginDir, "node_modules", "@lydell/node-pty"),
      );
    }

    // 2. Try require.resolve — works in dev setups where the module is on the
    //    Electron renderer's require path.
    try {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const resolved = require.resolve("@lydell/node-pty");
      // require.resolve returns …/index.js; we need the directory.
      candidates.push(path.dirname(resolved));
    } catch {
      /* not on the module path — skip */
    }

    // 3. Relative to process.cwd() — works when Obsidian is launched from the
    //    project root (development).
    candidates.push(
      path.join(process.cwd(), "node_modules", "@lydell/node-pty"),
    );

    for (const p of candidates) {
      const indexPath = path.join(p, "index.js");
      if (fs.existsSync(indexPath)) {
        return p;
      }
    }

    // Not found — let require throw with a useful error message.
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
