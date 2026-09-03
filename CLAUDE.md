# CLAUDE.md — Apidae

This file is the briefing document for Claude Code sessions on this repo.

## What this project is

**Apidae** is a macOS menu-bar utility that covers every display with a dark overlay so a Mac can keep working unattended without anyone (or anything) accidentally interacting with it. The metaphor is a beehive: when the hive is closed, the bees keep working inside.

- **Name**: Apidae (pronounced AY-pi-dee — the scientific family name for bees)
- **Domains**: `getapidae.com` (primary), `apidae.app` (secondary)
- **Bundle ID target**: `app.getapidae.mac`
- **URL scheme target**: `apidae://`
- **Target audience**: Cowork users, Claude Code users, AI-agent workflows on macOS — people who run long-running computer tasks (builds, agents, downloads, SSH sessions) and want to step away without locking the Mac in the OS sense.
- **Licence**: MIT, forked from [Lockpaw](https://github.com/sorkila/lockpaw) by Erik Nielsen. Erik's copyright and the MIT terms are preserved in `LICENSE`.

## Status

The Lockpaw → Apidae rebrand is complete: source folders, bundle id (`app.getapidae.mac`), URL scheme (`apidae://`), notification names, asset catalogue, palette (honey-yellow primary), copy, README, LICENSE, Homebrew cask, and CI/release workflows are all on the new brand. Bee artwork shipped in `Apidae/Resources/Assets.xcassets/` (AppIcon, Mascot, MenuBarIcon).

Sparkle auto-updates were removed during the cut and will return when releases ship from `getapidae.com/appcast.xml`. The previous `SUPublicEDKey` belonged to the original author and must never be reused — any future Sparkle reintroduction needs a freshly generated ed25519 keypair.

Code-signing identity, Apple ID, and team id in `scripts/build-release.sh` and the GitHub release workflow are TODO placeholders pending an Apple Developer account.

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
│  ├─ SleepPreventer        IOPMAssertion (display or idle) + periodic user-activity nudge
│  ├─ KeepAwakeController   Polls ActivityProviders, holds an assertion while one is busy
│  ├─ ClaudeActivityProvider Reads the Claude desktop app's AX tree for a running task
│  ├─ StatsRecorder         SQLite store for lock/unlock events
│  └─ StatsService          Query layer for the Stats tab
├─ Models/
│  ├─ LockState             .unlocked → .locking → .locked → .unlocking, validated
│  ├─ HotkeyConfig          UserDefaults wrapper + system-shortcut conflict detection
│  ├─ ActivityProvider      Protocol + ProviderActivity + ClaudeActivityRules (pure)
│  └─ KeepAwakeDecider      Pure hold/release logic with idle grace
├─ Views/
│  ├─ LockScreenView        Primary overlay: mascot, message, elapsed timer, auth button
│  ├─ AmbientScreenView     Secondary-display overlay (animated blobs only)
│  ├─ MenuBarView           Lock / Unlock / Settings / Quit dropdown
│  ├─ SettingsView          Form: hotkey, message, appearance, multi-display, perms
│  └─ OnboardingView        4-step wizard run on first launch
├─ Utilities/
│  ├─ Constants             appName, bundleIdentifier, urlScheme, Timing, Anim
│  ├─ Notifications         All Notification.Name extensions in one file
│  ├─ AccessibilityChecker  AXIsProcessTrusted + open-System-Settings helper
│  └─ AXTreeInspector       Capped depth-first walk of another app's AX tree
└─ Resources/Assets.xcassets/
   ├─ AppIcon.appiconset
   ├─ Mascot.imageset       Brand-neutral asset name; artwork = the bee
   ├─ MenuBarIcon.imageset  Template-rendered menu bar glyph
   └─ Colors/               ApidaeHoney (#F5B800 primary), ApidaeAmber, ApidaeError
```

## Key technical decisions worth knowing

- **Hotkey via CGEventTap on a background thread.** Carbon's `RegisterEventHotKey` is unreliable in `LSUIElement` apps because the main run loop doesn't pump events until first user interaction. `HotkeyManager` creates a `.cgSessionEventTap` with `.listenOnly` and runs `CFRunLoopRun()` on its own `Thread` so the tap fires immediately at launch. Requires Accessibility permission.
- **Two distinct event taps, two TCC permissions.** `HotkeyManager` is `.listenOnly` (passive observation) and only needs **Accessibility**. `InputBlocker` uses `.defaultTap` so it can return `nil` and actually *block* keyboard, scroll, and tablet events while locked — and `.defaultTap` requires **Input Monitoring** (`kTCCServiceListenEvent`) on top of Accessibility. Without Input Monitoring the input blocker silently fails to install the tap, the overlay still shows, but keystrokes pass through to whatever's underneath. Both permissions are requested by the onboarding flow but Input Monitoring is the one that's easiest to forget after a fresh install or rebuild. The unlock hotkey is checked inside the blocker callback and let through (well, posts a notification and returns nil). Mouse events pass through to the overlay so SwiftUI buttons remain clickable.
- **Tap re-enable on disabledByTimeout/disabledByUserInput.** Both taps re-enable themselves synchronously in their callback when macOS suspends them — otherwise the lock would silently break after a stall.
- **Overlay at `CGShieldingWindowLevel()`.** Highest level in the system; sits above Spotlight, Notification Center, screen savers. One overlay window per `NSScreen`. On `didChangeScreenParametersNotification`, windows are torn down and recreated, with a true cancellable debounce so a burst of monitor-connect events only triggers one rebuild. **Never call `window.close()` during fade-in** — it crashes in `_NSWindowTransformAnimation dealloc`. Use `orderOut(nil); contentView = nil` for cleanup instead.
- **State machine.** `LockState.canTransition(to:)` validates every move; `LockController.transitionTo()` is the only mutator and logs+rejects invalid jumps. State is also re-checked after async auth returns — the user can lose the session (Fast User Switch, sleep) mid-evaluation.
- **`@MainActor` controllers, `Task.detached` for `LAContext.evaluatePolicy`.** The system auth dialog needs the main thread, so awaiting it from MainActor would deadlock. The `Authenticator` hops off MainActor explicitly.
- **Toggle observer in `LockController.init`, not `.onReceive`.** `MenuBarExtra` content is lazily initialised on first menu open, so a SwiftUI-side observer wouldn't be live until the user clicks the menu. The hotkey must work without that.
- **Sleep prevention.** One `IOPMAssertion` per `SleepPreventer`: `PreventUserIdleDisplaySleep` when "Keep display on while locked" is on (the default), else `NoIdleSleep`. Taken on lock, released on unlock. An assertion alone does not stop the screen saver, the "lock after screen saver" timer, or on some systems the pre-sleep dim, so while the display must stay lit the lock timer also calls `nudgeUserActivityIfDue()`, which issues `IOPMAssertionDeclareUserActivity` every `Constants.Timing.userActivityNudgeInterval` (30s). Visible via `pmset -g assertions`.
- **Keep-awake without locking.** `KeepAwakeController` polls every `Constants.Timing.keepAwakePollInterval` (5s) off the main actor, asks each `ActivityProvider` whether its tool is busy, and holds a second, independent `SleepPreventer` (label "keeping the hive awake") while any is. `KeepAwakeDecider` adds `keepAwakeIdleGrace` (90s) so gaps between tool calls don't flap the assertion. The lock overlay and keep-awake can both hold assertions; IOKit keeps the Mac awake until both release. Settings keys: `keepAwakeEnabled` (default on), `keepAwakeKeepDisplayOn` (default off).
- **Claude detection is Accessibility-tree scraping.** `ClaudeActivityProvider` finds `com.anthropic.claudefordesktop`, sets `AXManualAccessibility` (Electron only builds the web AX tree when asked), and walks windows with `AXTreeInspector` (capped at 4000 elements, depth 48, 1s messaging timeout). Busy signals, in `ClaudeActivityRules`: a sidebar session row titled "Running …" or an `AXApplicationStatus` group described "Running" (covers every listed session), and the composer's "Stop response" button (the open conversation only). Idle rows carry an image described "Idle". Chat bubbles also contain `AXApplicationStatus` groups with an empty description, which must not count. Power assertions are useless as a signal: Claude holds a permanent Electron `NoIdleSleep` assertion. `scripts/ax-dump.swift` dumps the tree for when the UI changes; `scripts/diagnose.sh` gathers power, screen-saver and build info.
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

Unit tests in `ApidaeTests/` cover `LockState` transitions, `Constants` formatting, `HotkeyConfig` conflict detection, `SleepPreventer` assertion types, the stats recorder and service, `ClaudeActivityRules`, and `KeepAwakeDecider`. They are pure-logic tests; they don't touch the event taps, overlay windows, `LAContext`, or another app's AX tree.

**TCC gotcha.** Each Debug rebuild changes the binary signature, which invalidates the TCC permissions Apidae needs. Two services to reset:

```bash
tccutil reset Accessibility app.getapidae.mac
tccutil reset ListenEvent app.getapidae.mac    # "Input Monitoring" in System Settings UI
```

…then re-grant both in System Settings → Privacy & Security. Symptoms if you skip:

- **Accessibility missing**: hotkey doesn't fire at all (the listen-only tap can't be created).
- **Input Monitoring missing**: hotkey fires and the overlay shows, but the `.defaultTap` in `InputBlocker` silently fails so keyboard input passes through to whatever's underneath. This one is easy to mistake for a code regression — check Input Monitoring first.

CI runs build + tests on `macos-15` for every push to `main` and every PR (`.github/workflows/ci.yml`). Tagged releases (`v*`) trigger `release.yml`, which builds Release, signs with Developer ID, packages a DMG, notarizes, and creates a GitHub Release with the DMG attached. The release pipeline is **conditional on signing secrets being set**; absent the secrets, only the unsigned build runs.

## Distribution

- **DMG**: built by `scripts/build-release.sh` locally (or the release workflow on tag push). Uses `create-dmg` in CI; in the local script, builds an HFS+ R/W DMG and uses AppleScript-driven Finder layout, then converts to UDZO. The `Applications` entry is a Finder alias, not a symlink — symlinks render with a broken-icon overlay on Sonoma+. Both pipelines need real signing identities filled in (currently TODO placeholders).
- **Homebrew cask**: `homebrew/Casks/apidae.rb`. Tap from `brew tap mradeveci/apidae https://github.com/MrADeveci/getapidae` then `brew install --cask apidae`. The cask currently has `sha256 :no_check` and will need a real hash once a signed DMG ships.

## House style for working in this repo

- **No magic numbers, no scattered string literals.** Timing values go in `Constants.Timing`, animations in `Constants.Anim`, and every `Notification.Name` lives in `Utilities/Notifications.swift`.
- **`os.log` everywhere**, with `subsystem: "app.getapidae.mac"` and a `category` matching the type. No `print()`.
- **Tests required for new logic** in models or utilities; controllers and views are not unit-tested by design (they touch IOKit, CGEventTap, and AppKit).
- **Feature changes start with an issue.** The design is intentionally minimal; new UI needs discussion first.
- **Architecture decisions** that change a load-bearing pattern (state machine, event-tap threading, MainActor boundaries, overlay lifecycle) deserve a note in this file.

## Attribution

Apidae is a fork of [Lockpaw](https://github.com/sorkila/lockpaw) by Erik Nielsen, MIT-licensed. The original `LICENSE` file is preserved verbatim. The architecture decisions documented above are inherited from Lockpaw; the rebrand swaps the dog/watchdog metaphor for bees/hive but the engineering substance is Erik's.
