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

/** Paths to scan for available shells, in preference order. */
const KNOWN_SHELL_PATHS = [
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

/** Scan the filesystem for available shells. */
export function detectShells(): ShellEntry[] {
  const seen = new Set<string>();
  const result: ShellEntry[] = [];

  for (const shellPath of KNOWN_SHELL_PATHS) {
    const resolved = safeRealpath(shellPath);
    if (!resolved || seen.has(resolved)) continue;
    seen.add(resolved);

    if (!isExecutable(resolved)) continue;

    result.push({
      label: formatLabel(resolved),
      path: resolved,
      warning: getWarning(resolved),
    });
  }

  return result;
}

/**
 * Resolve the shell to use.
 *
 * Priority:
 * 1. Explicit user setting — returned as-is (PtyBridge validates and shows errors)
 * 2. Auto-detect — first detected shell (zsh preferred)
 * 3. "bash" bareword — last resort
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

  return "bash";
}

/**
 * Get shell-specific flags for login + interactive mode.
 *
 * bash / zsh:  -l (login) + -i (interactive) — sources profile + rc
 * fish:        -i only (no -l flag; login behaviour via fish_login)
 * sh / dash:   -i only (-l not universally supported)
 * Default:     -l -i (safe for most shells)
 */
export function shellFlags(shellPath: string): string[] {
  const name = path.basename(shellPath).toLowerCase();

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

function formatLabel(resolved: string): string {
  const name = path.basename(resolved);

  // For macOS /bin/bash — note it's the ancient 3.2
  if (resolved === "/bin/bash") {
    return `${resolved} — Bash 3.2 (⚠️ outdated)`;
  }

  return `${resolved} — ${name}`;
}

function getWarning(resolved: string): string | undefined {
  if (resolved === "/bin/bash") {
    return "This is the ancient macOS Bash 3.2. Consider installing bash via Homebrew, or switch to zsh.";
  }
  return undefined;
}
