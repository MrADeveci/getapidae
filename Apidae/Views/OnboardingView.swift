import SwiftUI
import Carbon

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var step = 0
    @State private var isRecording = false
    @State private var recordedKeyDisplay = HotkeyConfig.display
    @State private var accessibilityGranted = AccessibilityChecker.isEnabled
    @State private var accessibilityTimer: Timer?
    @State private var hotkeyConflict: String?
    @Environment(\.openSettings) private var openSettings

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Group {
                switch step {
                case 0: welcomeStep
                case 1: accessibilityStep
                case 2: hotkeyStep
                case 3: readyStep
                default: EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: 20)),
                removal: .opacity.combined(with: .offset(x: -20))
            ))
            .padding(.horizontal, 40)

            Spacer()

            // Progress + action
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color("ApidaeHoney") : .gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }

                Button {
                    advance()
                } label: {
                    Text(buttonLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(canAdvance
                                      ? Color("ApidaeHoney")
                                      : Color.gray.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .frame(width: 420, height: 500)
        .onDisappear {
            accessibilityTimer?.invalidate()
        }
    }

    private var canAdvance: Bool {
        if step == 1 && !accessibilityGranted { return false }
        return true
    }

    private var buttonLabel: String {
        switch step {
        case 1 where !accessibilityGranted: return "Waiting for access…"
        case 3: return "Get Started"
        default: return "Continue"
        }
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if step < totalSteps - 1 {
                step += 1
                if step == 1 { startAccessibilityPolling() }
            } else {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                NotificationCenter.default.post(name: .apidaeHotkeyPreferenceChanged, object: nil)
                hasCompletedOnboarding = true
                // Open Settings immediately — this activates the event pipeline
                // so the global hotkey works without needing to click the menu bar.
                openSettings()
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)

            VStack(spacing: 8) {
                Text("Welcome to Apidae")
                    .font(.title2.weight(.semibold))

                Text("Keeps your Mac awake while Claude works,\nand covers the screen when you step away.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Text("Apidae is a visual privacy tool, not a security lock. For real security, use your Mac's lock screen (Ctrl+Cmd+Q).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
    }

    // MARK: - Step 3: Hotkey (optional)

    private var hotkeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color("ApidaeHoney"))

            VStack(spacing: 8) {
                Text("A hotkey for the cover (optional)")
                    .font(.title2.weight(.semibold))

                Text("Press once to cover the screen, again to uncover.\nYou can change it or switch it off later in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            // Recorder
            Button {
                isRecording = true
            } label: {
                Group {
                    if isRecording {
                        Text("Press your shortcut…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color("ApidaeHoney").opacity(0.7))
                    } else {
                        Text(recordedKeyDisplay)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color("ApidaeHoney"))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color("ApidaeHoney").opacity(isRecording ? 0.15 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color("ApidaeHoney").opacity(isRecording ? 0.4 : 0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if let conflict = hotkeyConflict {
                Text(conflict)
                    .font(.caption)
                    .foregroundStyle(Color("ApidaeError"))
            } else {
                Text(isRecording ? "Press any modifier + key" : "Click to change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { setupKeyRecorder() }
    }

    // MARK: - Step 2: Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            ZStack {
                if accessibilityGranted {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Color("ApidaeHoney"))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("✋")
                        .font(.system(size: 36))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.3), value: accessibilityGranted)

            VStack(spacing: 8) {
                Text(accessibilityGranted ? "Access granted" : "Let Apidae see Claude")
                    .font(.title2.weight(.semibold))
                    .animation(.none, value: accessibilityGranted)

                if accessibilityGranted {
                    Text("Apidae can now see when Claude is working\nand block input while the cover is active.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                } else {
                    Text("Apidae needs Accessibility permission to see when\nClaude is working, to listen for the hotkey, and to\nblock keyboard input while the cover is active.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }

            if !accessibilityGranted {
                VStack(spacing: 10) {
                    Button {
                        AccessibilityChecker.promptIfNeeded()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            AccessibilityChecker.openSystemSettings()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gear")
                                .font(.system(size: 12))
                            Text("Open System Settings")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Color("ApidaeHoney"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color("ApidaeHoney").opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 4) {
                        Text("Find Apidae in the list and toggle it on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("This window will update automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Step 4: Ready

    private var readyStep: some View {
        VStack(spacing: 20) {
            // Menu bar illustration
            VStack(spacing: 0) {
                // Fake menu bar
                HStack(spacing: 12) {
                    Spacer()

                    // Other menu bar icons (generic)
                    Image(systemName: "wifi")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Image(systemName: "battery.75percent")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    // Apidae icon — highlighted
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color("ApidaeHoney").opacity(0.15))
                            .frame(width: 24, height: 20)

                        Image("MenuBarIcon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 12)
                            .foregroundStyle(Color("ApidaeHoney"))
                    }

                    // Clock
                    Text("11:21")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer().frame(width: 8)
                }
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.primary.opacity(0.06))
                )
            }
            .frame(width: 220)

            VStack(spacing: 8) {
                Text("Apidae lives in your menu bar")
                    .font(.title3.weight(.semibold))

                Text("Keep awake is already on. The bee icon goes solid\nwhile Apidae holds the Mac awake for Claude.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            // Hotkey reminder
            VStack(spacing: 4) {
                Text("Cover the screen with")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(recordedKeyDisplay)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color("ApidaeHoney"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color("ApidaeHoney").opacity(0.08))
                    )
            }
        }
    }

    // MARK: - Hotkey Recorder

    private func setupKeyRecorder() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }

            var parts: [String] = []
            if event.modifierFlags.contains(.command) { parts.append("Cmd") }
            if event.modifierFlags.contains(.shift) { parts.append("Shift") }
            if event.modifierFlags.contains(.option) { parts.append("Opt") }
            if event.modifierFlags.contains(.control) { parts.append("Ctrl") }

            guard !parts.isEmpty else { return event }

            if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
                parts.append(chars)
            }

            let display = parts.joined(separator: "+")

            // Check for conflicts with common system shortcuts
            if let conflict = HotkeyConfig.systemConflict(keyCode: Int(event.keyCode), modifiers: event.modifierFlags) {
                hotkeyConflict = "\(display) conflicts with \(conflict). Try another."
                return nil
            }

            recordedKeyDisplay = display
            hotkeyConflict = nil
            isRecording = false

            // Persist the hotkey to UserDefaults
            var carbonMods: Int = 0
            if event.modifierFlags.contains(.command) { carbonMods |= cmdKey }
            if event.modifierFlags.contains(.shift) { carbonMods |= shiftKey }
            if event.modifierFlags.contains(.option) { carbonMods |= optionKey }
            if event.modifierFlags.contains(.control) { carbonMods |= controlKey }
            HotkeyConfig.saveKeyCode(Int(event.keyCode))
            HotkeyConfig.saveModifiers(carbonMods)
            HotkeyConfig.saveDisplay(recordedKeyDisplay)
            // Don't post apidaeHotkeyPreferenceChanged here. The completion step
            // posts it once, so the hotkey registers when onboarding finishes.

            return nil
        }
    }

    // MARK: - Accessibility Polling

    private func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            DispatchQueue.main.async {
                accessibilityGranted = AccessibilityChecker.isEnabled
            }
        }
    }
}
