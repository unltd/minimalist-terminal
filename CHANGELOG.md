# Changelog

All notable changes to this project will be documented in this file.

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
- Platform support: macOS (x64, arm64), Linux (x64)
