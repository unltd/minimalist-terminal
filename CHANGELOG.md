# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.3.0] — 2026-08-04

### Added
- OSC 52 clipboard handler — tmux can write to the system clipboard
- GitHub Release workflow — auto-publish `main.js`/`manifest.json`/`styles.css` on `v*` tags
- `SECURITY.md` — security policy (private vulnerability reporting)

### Changed
- Clipboard paste: single code path via synchronous `ClipboardEvent` handler — no double paste
- Platform dependencies moved to `optionalDependencies`, OS matrix (ubuntu/macos/windows × Node 22) in CI

### Fixed
- `copy` event handled instead of blocked — prevents xterm.js duplicate handler
- node-pty Linux prebuilds added to `package-lock.json` for `npm ci`

### Removed
- Dockerfile + `.dockerignore` — dev container setup moved out of the plugin repo (project is desktop-only; build via npm, no Docker needed)

## [0.2.0] — 2026-07-31

### Added
- Windows support (basic ConPTY) — shell detection, PowerShell/CMD/WSL
- Clipboard: Cmd+C/V (Mac), Ctrl+Shift+C fallback, right-click paste
- Terminal.app Pro color theme (background #1e1e1e)
- CI: GitHub Actions — build + typecheck on `ubuntu-latest` (Node 18/20/22)
- CONTRIBUTING.md, CHANGELOG.md, `.env.example`
- Build/run/test/lint/deploy scripts + Makefile
- Dockerfile + `.dockerignore` (dev image)
- `.gitattributes` (`* text=auto`)
- Architecture diagram in README (Mermaid)
- Icon: `terminal` (Lucide)

### Changed
- Shell: zsh default with auto-detection (was hardcoded bash)
- Terminal tabs: no longer pinned (easy to close/reopen)
- docs/ → autodocs/ (internal dev docs separated from public docs)
- `.gitignore`: expanded patterns (IDE files, OS junk)
- Platform matrix: macOS primary dev, Windows basic, Linux untested

### Fixed
- Hardcoded paths removed from `findNodePty()` — uses vault basePath
- `.env` token replaced with placeholder
- `PtyBridge` crash guard on constructor failure (missing node-pty on Windows)
- Leaf no longer detached on shell exit — terminal stays visible with exit message

## [0.1.4] — 2026-07-27

### Added
- Shell selection via Settings Tab (auto-detect + custom path)
- Multi-session support — each terminal opens in a new tab
- In-plugin feedback button for user feedback

### Fixed
- Custom path field no longer snaps back to default on re-render
- ResizeObserver fit skipped when container has zero dimensions
- Terminal leafs pinned to prevent notes from opening in terminal group
- Clipboard: user-select none, Electron clipboard fallback

## [0.1.3] — 2026-07-20

### Added
- Gauge + pytest MVP test suite (CDP-based browser testing)
- GitHub issue/PR templates
- Screenshot debug skill for CDP screenshot analysis

### Fixed
- CDP vault targeting
- PTY write JS escaping
- CDP timeout calibration

## [0.1.2] — 2026-07-15

### Added
- Initial release with embedded terminal via xterm.js + node-pty
- Multi-terminal tabs (up to 10)
- Clipboard (Ctrl+Shift+C/V, right-click context menu)
- Auto-focus on open
- Configurable shell path
- Platform support: macOS (x64, arm64)
