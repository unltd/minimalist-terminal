import * as fs from "fs";
import * as path from "path";

/** Shell entry shown in the dropdown. */
export interface ShellEntry {
  /** Display label, e.g. "/bin/zsh — Zsh 5.x" */
  label: string;
  /** Full path to the executable */
  path: string;
  /** Whether this shell is outdated / has known issues */
  warning?: string;
}

/** Plugin settings persisted to Obsidian's data.json. */
export interface TerminalSettings {
  /** Full path to the shell executable. Empty = auto-detect (prefer zsh). */
  shell: string;
}

export const DEFAULT_SETTINGS: TerminalSettings = {
  shell: "",
};

/** Paths to scan for available shells, in preference order (Unix). */
const UNIX_SHELL_PATHS = [
  "/bin/zsh",
  "/opt/homebrew/bin/bash", // Homebrew ARM — modern bash
  "/usr/local/bin/bash",    // Homebrew x64
  "/bin/bash",
  "/opt/homebrew/bin/fish",
  "/usr/local/bin/fish",
  "/usr/bin/fish",
  "/bin/fish",
  "/usr/bin/zsh",
  "/bin/sh",
];

/** Executable names for PATH scanning on Windows, in preference order. */
const WINDOWS_SHELL_NAMES = [
  "pwsh.exe",          // PowerShell Core (cross-platform) — preferred
  "powershell.exe",    // Windows PowerShell 5.1
  "cmd.exe",           // Command Prompt
  "wsl.exe",           // WSL default distro
];

/** Scan the filesystem for available shells. */
export function detectShells(): ShellEntry[] {
  if (process.platform === "win32") {
    return detectWindowsShells();
  }
  return detectUnixShells();
}

function detectUnixShells(): ShellEntry[] {
  const seen = new Set<string>();
  const result: ShellEntry[] = [];

  for (const shellPath of UNIX_SHELL_PATHS) {
    const resolved = safeRealpath(shellPath);
    if (!resolved || seen.has(resolved)) continue;
    seen.add(resolved);

    if (!isExecutable(resolved)) continue;

    result.push({
      label: formatLabelUnix(resolved),
      path: resolved,
      warning: getWarning(resolved),
    });
  }

  return result;
}

/**
 * Detect Windows shells by scanning %PATH% for known executables.
 * Also checks well-known absolute paths that might not be on PATH.
 */
function detectWindowsShells(): ShellEntry[] {
  const seen = new Set<string>();
  const result: ShellEntry[] = [];

  for (const name of WINDOWS_SHELL_NAMES) {
    const fullPath = findInPath(name);
    if (fullPath && !seen.has(fullPath.toLowerCase())) {
      seen.add(fullPath.toLowerCase());
      result.push({ label: formatLabelWindows(fullPath, name), path: fullPath });
    }
  }

  return result;
}

/**
 * Search for an executable in %PATH%.
 * On Windows, also checks %PATHEXT% for valid extensions.
 */
function findInPath(exe: string): string | null {
  const pathEnv = process.env.PATH || "";
  const exts =
    process.platform === "win32" && process.env.PATHEXT
      ? process.env.PATHEXT.split(";").map((e) => e.toLowerCase())
      : [""];

  const dirs = pathEnv.split(path.delimiter);

  for (const dir of dirs) {
    if (!dir) continue;

    // Exact match first
    const exact = path.join(dir, exe);
    try {
      if (fs.existsSync(exact)) return exact;
    } catch {
      /* permission issue — skip */
    }

    // On Windows, try appending PATHEXT extensions
    if (process.platform === "win32") {
      const base = exe.replace(/\.exe$/i, "");
      for (const ext of exts) {
        if (!ext) continue;
        const full = path.join(dir, base + ext);
        try {
          if (fs.existsSync(full)) return full;
        } catch {
          /* skip */
        }
      }
    }
  }

  return null;
}

/**
 * Resolve the shell to use.
 *
 * Priority:
 * 1. Explicit user setting — returned as-is (PtyBridge validates and shows errors)
 * 2. Auto-detect — first detected shell (zsh preferred on Unix, pwsh on Windows)
 * 3. Fallback — "bash" on Unix, "cmd.exe" on Windows
 */
export function resolveShell(
  userSetting: string,
  detected: ShellEntry[],
): string {
  if (userSetting) {
    return userSetting;
  }

  if (detected.length > 0) {
    return detected[0].path;
  }

  return process.platform === "win32" ? "cmd.exe" : "bash";
}

/**
 * Get shell-specific flags for login + interactive mode.
 *
 * Unix:
 *   bash / zsh:  -l (login) + -i (interactive) — sources profile + rc
 *   fish:        -i only (no -l flag; login behaviour via fish_login)
 *   sh / dash:   -i only (-l not universally supported)
 *   Default:     -l -i (safe for most shells)
 *
 * Windows:
 *   cmd.exe:          (no flags — natively interactive)
 *   powershell.exe:   -NoLogo (suppress banner)
 *   pwsh.exe:         -NoLogo
 *   wsl.exe:          (no flags — launches default distro)
 *   Default:          (no flags)
 */
export function shellFlags(shellPath: string): string[] {
  const name = path.basename(shellPath).toLowerCase();

  // ── Windows shells ──────────────────────────────────────────
  if (name === "cmd.exe") {
    return [];
  }
  if (name === "powershell.exe" || name === "pwsh.exe") {
    return ["-NoLogo"];
  }
  if (name === "wsl.exe") {
    return [];
  }

  // ── Unix shells ─────────────────────────────────────────────
  switch (name) {
    case "fish":
      return ["-i"];
    case "sh":
    case "dash":
      return ["-i"];
    default:
      // bash, zsh, and most others
      return ["-l", "-i"];
  }
}

// ── helpers ──────────────────────────────────────────────────────────

function isExecutable(p: string): boolean {
  try {
    fs.accessSync(p, fs.constants.X_OK);
    return fs.statSync(p).isFile();
  } catch {
    return false;
  }
}

/** Like fs.realpathSync but returns null on error. */
function safeRealpath(p: string): string | null {
  try {
    return fs.realpathSync(p);
  } catch {
    return null;
  }
}

function formatLabelUnix(resolved: string): string {
  const name = path.basename(resolved);

  // For macOS /bin/bash — note it's the ancient 3.2
  if (resolved === "/bin/bash") {
    return `${resolved} — Bash 3.2 (⚠️ outdated)`;
  }

  return `${resolved} — ${name}`;
}

function formatLabelWindows(resolved: string, exeName: string): string {
  const label = path.basename(resolved);

  if (exeName === "pwsh.exe") {
    return `${resolved} — PowerShell Core`;
  }
  if (exeName === "powershell.exe") {
    return `${resolved} — Windows PowerShell`;
  }
  if (exeName === "cmd.exe") {
    return `${resolved} — Command Prompt`;
  }
  if (exeName === "wsl.exe") {
    return `${resolved} — WSL (default distro)`;
  }

  return `${resolved} — ${label}`;
}

function getWarning(resolved: string): string | undefined {
  if (resolved === "/bin/bash") {
    return "This is the ancient macOS Bash 3.2. Consider installing bash via Homebrew, or switch to zsh.";
  }
  return undefined;
}
