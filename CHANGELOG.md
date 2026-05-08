# Changelog

## [0.1.0] - 2026-05-08

Forked from Lockpaw 1.0.4 by Erik Nielsen and rebranded as Apidae.

- New name, bundle identifier `app.getapidae.mac`, URL scheme `apidae://`.
- Bee/hive metaphor replaces the dog/watchdog metaphor throughout.
- Sparkle auto-updates removed; will return when releases ship from getapidae.com.
- Colour palette: primary accent honey yellow (#F5B800), secondary deep amber.
- Default cover message: "Agents are working. Don't disturb the hive."

---

## Changelog (legacy: Lockpaw)

The entries below are Lockpaw release history, retained for context. They predate the Apidae rebrand.

### [1.0.4] - 2026-03-30

#### Fixed

- Fixed "Check for Updates" button not responding. Sparkle's standard update dialogs don't surface in menu bar (LSUIElement) apps. Replaced with inline feedback: spinner while checking, green checkmark for up-to-date, version badge for available updates, and error display.
- Deferred Sparkle updater startup to `applicationDidFinishLaunching` to prevent silent initialization failures.

### [1.0.3] - 2026-03-30

#### Fixed

- Fixed lock screen disappearing when connecting an external monitor during an active lock session. The screen change handler was calling `window.close()` on overlay windows that could still be mid-animation, causing a crash (`EXC_BAD_ACCESS` in `_NSWindowTransformAnimation dealloc`). Replaced with safe `orderOut` + `contentView = nil` cleanup.
- Fixed fake debounce in screen change handler. macOS fires multiple `didChangeScreenParametersNotification` events when a display connects — the old delay-based approach queued redundant handlers that could race. Now uses a proper cancellable debounce so only the last event in a burst triggers window recreation.

### [1.0.2] - 2025-05-25

- Initial public release with CI, DMG pipeline, Sparkle auto-updates, and Homebrew cask.
