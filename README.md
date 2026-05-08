<h1 align="center">Apidae</h1>

<p align="center">
  <strong>Cover your Mac screen with one hotkey. Everything keeps running.</strong><br>
  <em>No sleep. No display disconnect. No process interruption. Touch ID when you're back.</em>
</p>

<p align="center">
  <a href="https://github.com/MrADeveci/getapidae/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/MrADeveci/getapidae/ci.yml?branch=main&style=flat-square&label=CI&logo=github&logoColor=fff" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS%2014+-111?style=flat-square&logo=apple&logoColor=fff" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift%205.9-111?style=flat-square&logo=swift&logoColor=F05138" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/MIT-111?style=flat-square" alt="MIT License">
</p>

---

> When the hive is closed, the bees keep working. Apidae covers your Mac so background tasks — AI agents, builds, downloads, SSH sessions — stay alive while nothing accidentally interacts with them.

## Features

- ⌨️ **One hotkey** — cover and uncover with `Cmd+Shift+L` (customizable)
- 🔒 **Touch ID unlock** — or password fallback, just like your Mac
- 🖥️ **Every screen covered** — all displays, auto-detects new monitors
- 🤖 **Agents keep running** — AI coding tools, builds, downloads, SSH sessions
- 😴 **Prevents sleep** — IOKit assertion keeps your Mac awake while covered
- 🚫 **No analytics** — no data leaves your Mac, no accounts, no internet required

## Usage

| Action | How |
|--------|-----|
| Cover screen | Your hotkey (default `Cmd+Shift+L`) |
| Quick uncover | Same hotkey |
| Fallback uncover | Tap screen → Touch ID or password |
| Settings | Menu bar → Settings… |
| Change hotkey | Settings → Shortcuts → click to record |

## Install

### Build from source

```bash
brew install xcodegen
git clone https://github.com/MrADeveci/getapidae.git
cd getapidae
xcodegen generate
xcodebuild -scheme Apidae -configuration Release build
```

On first launch, grant **Accessibility** when prompted. A bee icon appears in your menu bar.

A signed DMG and Homebrew cask will follow once the project has an Apple Developer account and a release pipeline.

## Under the hood

**Hotkey** — `CGEvent.tapCreate` with `.listenOnly` on a dedicated background thread. Bypasses the LSUIElement activation issue that affects Carbon hotkeys in menu bar apps. Requires Accessibility permission.

**Input blocking** — separate `CGEventTap` intercepts all keyboard, scroll, and tablet events system-wide while covered. Mouse events pass through to the overlay (SwiftUI buttons need clicks). If macOS disables the tap, it re-enables synchronously in the callback.

**Window level** — `CGShieldingWindowLevel()`, the highest level in the system. Above Spotlight, Notification Center, screen savers, everything.

**Multi-display** — one overlay window per screen, recreated on hot-plug.

**State machine** — `LockState` enum with validated transitions. Every `transitionTo()` call is checked. State is verified again after async authentication returns.

**Sleep prevention** — `IOPMAssertion` keeps the Mac awake while covered.

**Auth** — `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` for Touch ID with password fallback. Rate-limited: 30s cooldown after 3 failed attempts.

## Security model

Apidae is a **visual privacy tool**, not a security boundary.

It guards against the accidental — a colleague, a cat, your own muscle memory while agents run. Not the intentional.

<details>
<summary><strong>What it does</strong></summary>
<br>

- Overlay at highest system window level
- Event tap blocks all keyboard/scroll input
- Fast User Switching cancels auth, keeps cover active
- Accessibility revocation detected and handled (force uncover with warning)
- URL scheme rate-limited (100ms debounce)
- Debug escape hatch compile-gated (`#if DEBUG`)
- State machine validates every transition
- Hotkey conflict detection against system shortcuts

</details>

<details>
<summary><strong>What it doesn't do</strong></summary>
<br>

- Prevent `pkill Apidae`
- Block synthetic events (AppleScript, Accessibility API)
- Survive kernel-level access
- Protect against screen recording during overlay fade-in

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
│  ├─ LockController              State machine, cover/uncover orchestration
│  ├─ Authenticator               LAContext · Touch ID · password fallback
│  ├─ InputBlocker                CGEventTap · keyboard/scroll blocking
│  ├─ HotkeyManager               CGEventTap · global hotkey detection
│  ├─ OverlayWindowManager        NSWindow · multi-display · shielding level
│  └─ SleepPreventer              IOKit · idle sleep assertion
├─ Models/
│  ├─ LockState                   .unlocked → .locking → .locked → .unlocking
│  └─ HotkeyConfig                Centralized hotkey UserDefaults access
├─ Views/
│  ├─ LockScreenView              Mascot · glow · progressive disclosure
│  ├─ MenuBarView                 Dropdown · cover/uncover/quit
│  ├─ SettingsView                Native Form · hotkey recorder · appearance
│  └─ OnboardingView              4-step wizard · hotkey · accessibility
├─ Utilities/
│  ├─ Constants                   Timing, animations, formatting
│  ├─ Notifications               All Notification.Name in one place
│  └─ AccessibilityChecker        AXIsProcessTrusted + System Settings
└─ Resources/
   └─ Assets                      App icon, mascot, menu bar icon, colors
```

## CI

Pushes to `main` and PRs run build + 34 unit tests via GitHub Actions.

## Attribution

Apidae is a fork of [Lockpaw](https://github.com/sorkila/lockpaw) by Erik Nielsen, released under the MIT License. The original Lockpaw copyright and licence are preserved in `LICENSE`. The architecture and engineering decisions documented above are inherited from Lockpaw; the rebrand swaps the dog/watchdog metaphor for bees/hive.

## Licence

MIT. See [LICENSE](LICENSE).
