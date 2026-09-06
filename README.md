<h1 align="center">Apidae</h1>

<p align="center">
  <strong>Apidae watches Claude and keeps your Mac awake while it works.</strong><br>
  <em>Nothing to install into your agent. No hooks. No hotkeys to learn. Run it and it just works.</em>
</p>

<p align="center">
  <a href="https://github.com/MrADeveci/getapidae/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/MrADeveci/getapidae/ci.yml?branch=main&style=flat-square&label=CI&logo=github&logoColor=fff" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS%2014+-111?style=flat-square&logo=apple&logoColor=fff" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift%205.9-111?style=flat-square&logo=swift&logoColor=F05138" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/MIT-111?style=flat-square" alt="MIT License">
</p>

---

> A Cowork or Claude Code task can run for an hour. Your Mac's idle timer does not know that. Apidae does: it sees the task running in the Claude desktop app and holds the Mac awake until the task is done, then lets go. When you want to walk away, it can also cover every screen so nothing and nobody interrupts the hive.

## What it does

**Keeps the Mac awake while Claude works.** Apidae reads the Claude desktop app through the Accessibility API and holds a power assertion whenever a Cowork session or a Claude Code session is running, or a reply is streaming. It releases 90 seconds after the last sign of activity, so short pauses between tool calls do not cause flapping. The menu bar shows what the watcher currently sees, and the bee glyph goes solid while a hold is active. On by default, nothing to configure.

**Covers the screen when you step away.** One click in the menu bar (or a hotkey, if you want one) puts a dark overlay across every display, blocks keyboard input, and keeps the display lit so the lock screen never goes black. Unlock with Touch ID or your password. Everything underneath keeps running.

**Tells you how much it saved.** A Stats tab records every cover session in a local SQLite database: today, this week, all time, and recent activity.

## Why not just install a hook?

Tools like Lockpaw ask each agent to call them when it finishes, which means installing a hook into every agent's config. That works for CLI agents, but the Claude desktop app has no hook system, so Cowork sessions are invisible to that approach. Apidae does not need to be told. It looks at what Claude is doing and acts on its own, which is why it works with Cowork on day one and why there is nothing to set up.

## Features

- 👁️ **Automatic keep awake**: watches the Claude desktop app and holds the Mac awake while a task runs, with a 90 second grace period
- 📊 **Live status**: menu bar line shows Claude idle, busy, or not running, and how long the current hold has lasted
- 🖥️ **Every screen covered**: all displays, auto detects new monitors, ambient animation or mirrored cover on secondary screens
- 🔒 **Touch ID unlock**: or password fallback, just like your Mac
- 💡 **Display stays lit**: the cover pairs a display assertion with a periodic user activity nudge, so the screen saver and lock timer cannot take over
- 📈 **Stats**: local record of cover sessions, today, this week, and all time
- ⌨️ **Optional hotkey**: `Cmd+Shift+L` by default, recordable, or switch it off entirely
- 🔌 **URL scheme**: `apidae://lock`, `unlock`, `toggle` for scripts and automations
- 🚫 **No analytics**: no data leaves your Mac, no accounts, no network calls at all

## Usage

| Action | How |
|--------|-----|
| Keep the Mac awake while Claude works | Nothing. It is on by default. Watch the status line in the menu bar |
| Turn keep awake off or on | Menu bar toggle, or Settings > General > Keep Awake |
| Also keep the display on during a hold | Settings > General > Keep Awake > Also keep the display on |
| Cover the screen | Menu bar > Lock Screen, or your hotkey (default `Cmd+Shift+L`) |
| Uncover | Same hotkey, or click the screen and use Touch ID or password |
| See stats | Settings > Stats |
| Change or disable the hotkey | Settings > General > Shortcuts |

## Install

### Download

Grab `Apidae.dmg` from the [latest release](https://github.com/MrADeveci/getapidae/releases/latest), open it and drag Apidae to Applications.

Releases marked **pre release** are not yet signed with an Apple Developer ID, so macOS will say it cannot verify the app. Double click Apidae once and dismiss the warning, then go to System Settings > Privacy & Security, scroll down and click **Open Anyway**. You only do this once per version. Signed and notarised builds will follow.

### Build from source

```bash
brew install xcodegen
git clone https://github.com/MrADeveci/getapidae.git
cd getapidae
xcodegen generate
xcodebuild -scheme Apidae -configuration Release build
```

On first launch, grant **Accessibility** when prompted. Apidae needs it to read the Claude app's accessibility tree, to listen for the hotkey, and to block input while covered. macOS will also ask for **Input Monitoring** the first time Apidae blocks input; without it the overlay still appears but keystrokes pass through underneath. A bee icon appears in your menu bar.

A Homebrew cask lives in `homebrew/` and will be published as a tap once releases are signed.

## Under the hood

**Keep awake**: `KeepAwakeController` polls a list of `ActivityProvider`s every 5 seconds off the main actor. `ClaudeActivityProvider` walks the accessibility tree of `com.anthropic.claudefordesktop` with a depth capped `AXTreeInspector` looking for two signals: a sidebar row titled "Running …" with an `AXApplicationStatus` group, or a composer button described "Stop response". Either counts as busy. `KeepAwakeDecider` is pure logic (no AppKit) and decides hold or release given the readings, the last busy time, and the grace period, so it is fully unit tested. Providers for other tools can be added by conforming to the protocol.

**Sleep prevention**: `SleepPreventer` wraps an `IOPMAssertion` (idle sleep, or display sleep when asked) and declares user activity every 30 seconds while an assertion is held, which is what keeps the lock overlay lit. The keep awake watcher and the lock overlay each own a `SleepPreventer`; IOKit keeps the Mac awake until both let go.

**Hotkey**: `CGEvent.tapCreate` with `.listenOnly` on a dedicated background thread. Bypasses the LSUIElement activation issue that affects Carbon hotkeys in menu bar apps. Requires Accessibility permission. Can be disabled in Settings.

**Input blocking**: separate `CGEventTap` intercepts all keyboard, scroll, and tablet events system wide while covered. Mouse events pass through to the overlay (SwiftUI buttons need clicks). If macOS disables the tap, it re-enables synchronously in the callback. Requires Input Monitoring.

**Window level**: `CGShieldingWindowLevel()`, the highest level in the system. Above Spotlight, Notification Center, screen savers, everything.

**Multi display**: one overlay window per screen, recreated on hot plug. Secondary displays show either an ambient animation or a mirror of the primary cover.

**State machine**: `LockState` enum with validated transitions. Every `transitionTo()` call is checked. State is verified again after async authentication returns.

**Stats**: `StatsRecorder` writes lock and unlock events to SQLite in Application Support; `StatsService` is the query layer behind the Stats tab.

**Auth**: `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` for Touch ID with password fallback. Rate limited: 30s cooldown after 3 failed attempts.

## Security model

Apidae is a **visual privacy tool**, not a security boundary.

It guards against the accidental: a colleague, a cat, your own muscle memory while agents run. Not the intentional.

<details>
<summary><strong>What it does</strong></summary>
<br>

- Overlay at highest system window level
- Event tap blocks all keyboard/scroll input
- Fast User Switching cancels auth, keeps cover active
- Accessibility revocation detected and handled (force uncover with warning; keep awake pauses and says so)
- URL scheme rate limited (100ms debounce)
- Debug escape hatch compile gated (`#if DEBUG`)
- State machine validates every transition
- Hotkey conflict detection against system shortcuts

</details>

<details>
<summary><strong>What it doesn't do</strong></summary>
<br>

- Prevent `pkill Apidae`
- Block synthetic events (AppleScript, Accessibility API)
- Survive kernel level access
- Protect against screen recording during overlay fade in
- Read anything from Claude beyond the accessibility labels needed to tell busy from idle

For real security: `Ctrl+Cmd+Q`.

</details>

## URL scheme

```
apidae://lock              Cover the screen
apidae://unlock            Uncover with Touch ID
apidae://unlock-password   Uncover with password
apidae://toggle            Toggle cover state
```

## Architecture

```
Apidae/
├─ ApidaeApp                      Entry, MenuBarExtra, AppDelegate, onboarding
├─ Controllers/
│  ├─ KeepAwakeController         Polls providers, holds an assertion while one is busy
│  ├─ ClaudeActivityProvider      Reads the Claude desktop app's AX tree for a running task
│  ├─ LockController              State machine, cover/uncover orchestration
│  ├─ Authenticator               LAContext · Touch ID · password fallback
│  ├─ InputBlocker                CGEventTap · keyboard/scroll blocking
│  ├─ HotkeyManager               CGEventTap · global hotkey detection
│  ├─ OverlayWindowManager        NSWindow · multi display · shielding level
│  ├─ SleepPreventer              IOKit assertion · periodic user activity nudge
│  ├─ StatsRecorder               SQLite store for lock/unlock events
│  └─ StatsService                Query layer for the Stats tab
├─ Models/
│  ├─ ActivityProvider            Protocol · ProviderActivity · ClaudeActivityRules
│  ├─ KeepAwakeDecider            Pure hold/release logic with idle grace
│  ├─ LockState                   .unlocked → .locking → .locked → .unlocking
│  └─ HotkeyConfig                Centralized hotkey UserDefaults access
├─ Views/
│  ├─ LockScreenView              Mascot · message · elapsed timer · auth button
│  ├─ AmbientScreenView           Secondary display animation
│  ├─ MenuBarView                 Lock/unlock · keep awake status and toggle · settings
│  ├─ SettingsView                Tab container: General / Stats / About
│  ├─ GeneralSettingsView         Lock screen · keep awake · shortcuts · permissions
│  ├─ StatsSettingsView           Today · week chart · all time · recent activity
│  ├─ AboutSettingsView           Version · links · licence
│  └─ OnboardingView              4 step wizard · accessibility · optional hotkey
├─ Utilities/
│  ├─ Constants                   Timing, animations, providers, formatting
│  ├─ Notifications               All Notification.Name in one place
│  ├─ AccessibilityChecker        AXIsProcessTrusted + System Settings
│  └─ AXTreeInspector             Capped depth first walk of another app's AX tree
└─ Resources/
   └─ Assets                      App icon, mascot, menu bar icon, colors

scripts/
├─ diagnose.sh                    Power assertions, display state, Apidae log tail
└─ ax-dump.swift                  Dump the Claude app's accessibility tree
```

## Roadmap

- Cover the screen automatically when Claude is busy and you have been away for a while
- Keep awake sessions in Stats
- Providers for other agents
- Signed DMG, Homebrew cask, auto updates

## CI

Pushes to `main` and PRs run build + 70 unit tests via GitHub Actions.

## Attribution

Apidae started as a fork of [Lockpaw](https://github.com/sorkila/lockpaw) 1.0.4 by Erik Nielsen, released under the MIT License. The original Lockpaw copyright and licence are preserved in `LICENSE`. The lock overlay, input blocking, hotkey handling, state machine and authentication flow described above come from Lockpaw. The keep awake watcher, activity providers, stats, and the bee/hive brand are Apidae's own.

## Licence

MIT. See [LICENSE](LICENSE).
