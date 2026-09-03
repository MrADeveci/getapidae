import AppKit
import os.log

private let logger = Logger(subsystem: "app.getapidae.mac", category: "ClaudeActivityProvider")

/// Watches the Claude desktop app (Cowork and Claude Code sessions) through the
/// Accessibility API. See `ClaudeActivityRules` for what counts as busy.
final class ClaudeActivityProvider: ActivityProvider {
    let id = "claude"
    let displayName = Constants.Providers.claudeDisplayName

    func checkActivity() -> ProviderActivity {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Constants.Providers.claudeBundleIdentifier
        }
        guard let app = running.first else { return .notRunning }
        guard AXIsProcessTrusted() else {
            logger.debug("Accessibility not granted; cannot inspect Claude")
            return .idle
        }
        if let detail = AXTreeInspector.firstMatch(pid: app.processIdentifier, predicate: ClaudeActivityRules.busySignal) {
            return .busy(detail: detail)
        }
        return .idle
    }
}
