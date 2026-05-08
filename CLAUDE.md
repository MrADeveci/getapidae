# CLAUDE.md — Apidae

This file is the briefing document for Claude Code sessions on this repo. It describes the project as it stands today, including the in-flight rename from Lockpaw to Apidae.

## What this project is

**Apidae** is a macOS menu-bar utility that covers every display with a dark overlay so a Mac can keep working unattended without anyone (or anything) accidentally interacting with it. The metaphor is a beehive: when the hive is closed, the bees keep working inside.

- **Name**: Apidae (pronounced AY-pi-dee — the scientific family name for bees)
- **Domains**: `getapidae.com` (primary), `apidae.app` (secondary)
- **Bundle ID target**: `app.getapidae.mac`
- **URL scheme target**: `apidae://`
- **Target audience**: Cowork users, Claude Code users, AI-agent workflows on macOS — people who run long-running computer tasks (builds, agents, downloads, SSH sessions) and want to step away without locking the Mac in the OS sense.
- **Licence**: MIT, forked from [Lockpaw](https://github.com/sorkila/lockpaw) by Erik Nielsen. Erik's copyright and the MIT terms are preserved in `LICENSE`.

## Status: rebrand in progress

The repo on disk is still **Lockpaw** at the time of writing. A full rename plan covering bundle ID, source folders, type names, notification names, asset catalog, Sparkle removal, README rewrite, Homebrew cask, and the Raycast extension was prepared in conversation. When working in this repo, check whether the rename has been executed (look for `Apidae/` and `ApidaeTests/` directories, `project.yml` `name: Apidae`, `Constants.appName == "Apidae"`) before assuming brand state.

Sparkle auto-updates were planned for removal during the rebrand cut and to be reintroduced later when releases start shipping from `getapidae.com/appcast.xml`. If you see no `Sparkle` references in `project.yml`, that decision was followed through. The previous `SUPublicEDKey` belonged to the original author and should never be reused — any future Sparkle reintroduction must use a freshly generated ed25519 keypair.

## Architecture at a glance

macOS 14+ SwiftUI app, `LSUIElement = true` (menu-bar-only). XcodeGen generates `Apidae.xcodeproj` from `project.yml`. The app has no sandbox (`com.apple.security.app-sandbox = false`) because it needs Accessibility access for system-wide event taps.

```
Apidae/                    (was: Lockpaw/)
├─ ApidaeApp.swift         Entry, MenuBarExtra, AppDelegate, onboarding window
├─ Controllers/
│  ├─ LockController        @MainActor state machine, orchestrates everything
│  ├─ Authenticator         LAContext (Touch ID + password fallback)
│  ├─ InputBlocker          CGEventTap on caller's run loop (default tap, intercepts)
│  ├─ HotkeyManager         CGEventTap on a dedicated background thread (listen-only)
│  ├─ OverlayWindowManager  NSWindow per screen at CGShieldingWindowLevel
│  └─ SleepPreventer        IOPMAssertion (kIOPMAssertionTypeNoIdleSleep)
├─ Models/
│  ├─ LockState             .unlocked → .locking → .locked → .unlocking, validated
│  └─ HotkeyConfig          UserDefaults wrapper + system-shortcut conflict detection
├─ Views/
│  ├─ LockScreenView        Primary overlay: mascot, message, elapsed timer, auth button
│  ├─ AmbientScreenView     Secondary-display overlay (animated blobs only)
│  ├─ MenuBarView           Lock / Unlock / Settings / Quit dropdown
│  ├─ SettingsView          Form: hotkey, message, appearance, multi-display, perms
│  └─ OnboardingView        4-step wizard run on first launch
├─ Utilities/
│  ├─ Constants             appName, bundleIdentifier, urlScheme, Timing, Anim
│  ├─ Notifications         All Notification.Name extensions in one file
│  └─ AccessibilityChecker  AXIsProcessTrusted + open-System-Settings helper
└─ Resources/Assets.xcassets/
   ├─ AppIcon.appiconset
   ├─ Mascot.imageset       Brand-neutral asset name; artwork = the bee
   ├─ MenuBarIcon.imageset  Template-rendered menu bar glyph
   └─ Colors/               ApidaeTeal, ApidaeAmber, ApidaeError, (+Success, Violet — currently unreferenced)
```

## Key technical decisions worth knowing

- **Hotkey via CGEventTap on a background thread.** Carbon's `RegisterEventHotKey` is unreliable in `LSUIElement` apps because the main run loop doesn't pump events until first user interaction. `HotkeyManager` creates a `.cgSessionEventTap` with `.listenOnly` and runs `CFRunLoopRun()` on its own `Thread` so the tap fires immediately at launch. Requires Accessibility permission.
- **Two distinct event taps.** `HotkeyManager` is `.listenOnly` (passive observation). `InputBlocker` uses `.defaultTap` so it can return `nil` and actually *block* keyboard, scroll, and tablet events while locked. The unlock hotkey is checked inside the blocker callback and let through (well, posts a notification and returns nil). Mouse events pass through to the overlay so SwiftUI buttons remain clickable.
- **Tap re-enable on disabledByTimeout/disabledByUserInput.** Both taps re-enable themselves synchronously in their callback when macOS suspends them — otherwise the lock would silently break after a stall.
- **Overlay at `CGShieldingWindowLevel()`.** Highest level in the system; sits above Spotlight, Notification Center, screen savers. One overlay window per `NSScreen`. On `didChangeScreenParametersNotification`, windows are torn down and recreated, with a true cancellable debounce so a burst of monitor-connect events only triggers one rebuild. **Never call `window.close()` during fade-in** — it crashes in `_NSWindowTransformAnimation dealloc`. Use `orderOut(nil); contentView = nil` for cleanup instead.
- **State machine.** `LockState.canTransition(to:)` validates every move; `LockController.transitionTo()` is the only mutator and logs+rejects invalid jumps. State is also re-checked after async auth returns — the user can lose the session (Fast User Switch, sleep) mid-evaluation.
- **`@MainActor` controllers, `Task.detached` for `LAContext.evaluatePolicy`.** The system auth dialog needs the main thread, so awaiting it from MainActor would deadlock. The `Authenticator` hops off MainActor explicitly.
- **Toggle observer in `LockController.init`, not `.onReceive`.** `MenuBarExtra` content is lazily initialised on first menu open, so a SwiftUI-side observer wouldn't be live until the user clicks the menu. The hotkey must work without that.
- **Sleep prevention.** Single `IOPMAssertion` of type `kIOPMAssertionTypeNoIdleSleep` taken on lock, released on unlock. Visible via `pmset -g assertions`.
- **Auth rate-limiting.** 3 failed attempts → 30s cooldown. Limit and cooldown live in `Constants.Timing`.
- **URL scheme is rate-limited too.** 100ms debounce in `AppDelegate.application(_:open:)` to defuse repeated triggers from external launchers.
- **Debug-only escape hatch.** `InputBlocker` has a `#if DEBUG` Cmd+Shift+Q kill-switch that calls `NSApplication.terminate`. Compile-gated so it can never ship.
- **Hotkey conflict detection.** `HotkeyConfig.systemConflict(keyCode:modifiers:)` rejects common system shortcuts (Cmd+Q, Cmd+Tab, Cmd+Space, Ctrl+Cmd+Q, …) at recording time so users don't shoot themselves in the foot.

## Security model

Apidae is a **visual privacy tool, not a security boundary.** It guards against accidental input — colleagues, cats, your own muscle memory — while a Mac is doing unattended work. It does *not*:

- Prevent `pkill Apidae`.
- Block synthetic events sent through AppleScript or the Accessibility API.
- Survive root or kernel-level access.
- Protect against screen recording during the overlay fade-in.

For real lock semantics, the OS lock screen (Ctrl+Cmd+Q) is what to use. The Settings → About copy and onboarding both say this explicitly.

## Build, test, run

```bash
brew install xcodegen           # one-time
xcodegen generate                # regenerates Apidae.xcodeproj from project.yml
xcodebuild -project Apidae.xcodeproj -scheme Apidae -configuration Debug build
xcodebuild -project Apidae.xcodeproj -scheme Apidae -configuration Debug test
```

There are 34 unit tests across `ApidaeTests/` covering `LockState` transitions, `Constants` formatting, and `HotkeyConfig` conflict detection. They are pure-logic tests; they don't touch the event taps, overlay windows, or `LAContext`.

**TCC gotcha.** Each Debug rebuild changes the binary signature, which invalidates Accessibility permission. After every build, run:

```bash
tccutil reset Accessibility app.getapidae.mac
```

…then re-grant Accessibility in System Settings. Without this, the hotkey and input blocker silently fail.

CI runs build + tests on `macos-15` for every push to `main` and every PR (`.github/workflows/ci.yml`). Tagged releases (`v*`) trigger `release.yml`, which builds Release, signs with Developer ID, packages a DMG, notarizes, and creates a GitHub Release with the DMG attached. The release pipeline is **conditional on signing secrets being set**; absent the secrets, only the unsigned build runs.

## Distribution

- **DMG**: built by `scripts/build-release.sh` locally (or the release workflow on tag push). Uses `create-dmg` in CI; in the local script, builds an HFS+ R/W DMG and uses AppleScript-driven Finder layout, then converts to UDZO. The `Applications` entry is a Finder alias, not a symlink — symlinks render with a broken-icon overlay on Sonoma+.
- **Homebrew cask**: `homebrew/Casks/apidae.rb`. Tap from `brew tap <gh-org>/apidae <repo-url>` then `brew install --cask apidae`.
- **Raycast extension**: `apidae-raycast/`. Four commands (Lock, Unlock with Touch ID, Unlock with Password, Toggle), each just calls `apidae://<command>` via `open()`. Useful because Raycast lets users assign their own hotkeys per command, beyond Apidae's single global one.

## House style for working in this repo

- **No magic numbers, no scattered string literals.** Timing values go in `Constants.Timing`, animations in `Constants.Anim`, and every `Notification.Name` lives in `Utilities/Notifications.swift`.
- **`os.log` everywhere**, with `subsystem: "app.getapidae.mac"` and a `category` matching the type. No `print()`.
- **Tests required for new logic** in models or utilities; controllers and views are not unit-tested by design (they touch IOKit, CGEventTap, and AppKit).
- **Feature changes start with an issue.** The design is intentionally minimal; new UI needs discussion first.
- **Architecture decisions** that change a load-bearing pattern (state machine, event-tap threading, MainActor boundaries, overlay lifecycle) deserve a note in this file.

## Attribution

Apidae is a fork of [Lockpaw](https://github.com/sorkila/lockpaw) by Erik Nielsen, MIT-licensed. The original `LICENSE` file is preserved verbatim. The architecture decisions documented above are inherited from Lockpaw; the rebrand swaps the dog/watchdog metaphor for bees/hive but the engineering substance is Erik's.
