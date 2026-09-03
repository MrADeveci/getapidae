import SwiftUI

struct MenuBarView: View {
    @ObservedObject var controller: LockController
    @ObservedObject var keepAwake: KeepAwakeController
    @AppStorage(KeepAwakeController.enabledKey) private var keepAwakeEnabled = true

    var body: some View {
        Group {
            if controller.state == .unlocked {
                Button {
                    controller.lock(trigger: .menu)
                } label: {
                    Label("Lock Screen", systemImage: "lock.fill")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            } else {
                Button {
                    controller.requestUnlock(trigger: .menu)
                } label: {
                    Label("Unlock with Touch ID", systemImage: "touchid")
                }

                Button {
                    controller.requestPasswordUnlock(trigger: .menu)
                } label: {
                    Label("Unlock with Password", systemImage: "keyboard")
                }

                Divider()

                Label {
                    Text("Locked for \(Constants.formatElapsedTime(controller.elapsedTime))")
                        .foregroundStyle(.primary.opacity(0.7))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                } icon: {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            KeepAwakeMenuSection(keepAwake: keepAwake, enabled: $keepAwakeEnabled)

            Divider()

            SettingsLink {
                Text("Settings\u{2026}")
            }
            .keyboardShortcut(",")

            Button("Quit Apidae") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .onReceive(NotificationCenter.default.publisher(for: .apidaeLock)) { note in
            if controller.state == .unlocked {
                controller.lock(trigger: note.trigger)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apidaeUnlock)) { note in
            if controller.state == .locked {
                controller.requestUnlock(trigger: note.trigger)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apidaeUnlockPassword)) { note in
            if controller.state == .locked {
                controller.requestPasswordUnlock(trigger: note.trigger)
            }
        }
    }
}

/// Menu rows for the keep-awake watcher: a status line plus the on/off toggle.
struct KeepAwakeMenuSection: View {
    @ObservedObject var keepAwake: KeepAwakeController
    @Binding var enabled: Bool

    var body: some View {
        Label {
            Text(statusText)
                .foregroundStyle(.primary.opacity(0.7))
                .font(.system(size: 12, weight: .medium))
        } icon: {
            Image(systemName: statusSymbol)
                .foregroundStyle(keepAwake.state.isHolding ? Color("ApidaeHoney") : .secondary)
        }

        Toggle("Keep Awake While \(providerNames) Works", isOn: $enabled)
    }

    private var providerNames: String {
        keepAwake.providers.map(\.displayName).joined(separator: ", ")
    }

    private var statusSymbol: String {
        switch keepAwake.state {
        case .holding: return "bolt.fill"
        case .disabled: return "bolt.slash"
        case .needsAccessibility: return "exclamationmark.triangle"
        case .watching: return "eye"
        }
    }

    private var statusText: String {
        switch keepAwake.state {
        case .disabled:
            return "Keep awake is off"
        case .needsAccessibility:
            return "Keep awake needs Accessibility access"
        case .holding(_, let detail):
            let elapsed = Constants.formatElapsedTime(keepAwake.holdElapsed)
            return "Keeping awake, \(detail) (\(elapsed))"
        case .watching(let readings):
            let parts = readings.sorted { $0.key < $1.key }.map { name, activity -> String in
                switch activity {
                case .notRunning: return "\(name) not running"
                case .idle: return "\(name) idle"
                case .busy: return "\(name) busy"
                }
            }
            return parts.isEmpty ? "Watching" : "Watching: " + parts.joined(separator: ", ")
        }
    }
}
