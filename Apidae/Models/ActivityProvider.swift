import Foundation

/// What a watched tool is doing right now, as far as Apidae can tell.
enum ProviderActivity: Equatable, Sendable {
    /// The tool's process is not running.
    case notRunning
    /// Running, but nothing looks like work in progress.
    case idle
    /// Working. `detail` is a short human-readable reason (what tripped the detector).
    case busy(detail: String)

    var isBusy: Bool {
        if case .busy = self { return true }
        return false
    }
}

/// A source of "is this tool working?" signals. Claude is the first; others can be
/// added by conforming and appending to `KeepAwakeController`'s provider list.
///
/// `checkActivity()` may block briefly (Accessibility calls round-trip to the target
/// process), so the controller always calls it off the main actor.
protocol ActivityProvider: AnyObject, Sendable {
    /// Stable identifier, used for logging and settings keys.
    var id: String { get }
    /// Name shown in the menu and settings, e.g. "Claude".
    var displayName: String { get }
    func checkActivity() -> ProviderActivity
}

/// A flattened accessibility element, just the attributes the busy rules look at.
/// Kept as a plain struct so the rules are testable without AXUIElement.
struct AXElementSummary: Equatable, Sendable {
    var role: String = ""
    var subrole: String = ""
    var title: String = ""
    var description: String = ""
    var value: String = ""
}

/// Rules for spotting an in-progress task in the Claude desktop app's accessibility
/// tree. Two independent signals, either is enough:
///
/// 1. Sidebar: a session row is titled "Running <session name>" and carries an
///    `AXApplicationStatus` group described "Running". Idle rows carry an image
///    described "Idle". This covers every listed session, not just the open one.
/// 2. Composer: while a reply is streaming the send button becomes a button
///    described "Stop response".
///
/// If Anthropic reshuffles the UI these are the strings to revisit.
enum ClaudeActivityRules {
    static let runningTitlePrefix = "Running "
    static let runningStatusDescription = "Running"
    static let applicationStatusSubrole = "AXApplicationStatus"
    static let stopResponseDescription = "Stop response"

    /// Returns a short reason if the element indicates work in progress, else nil.
    static func busySignal(for element: AXElementSummary) -> String? {
        if element.role == "AXGroup",
           element.subrole == applicationStatusSubrole,
           element.description == runningStatusDescription {
            return "a session is running"
        }
        if element.role == "AXButton", element.title.hasPrefix(runningTitlePrefix) {
            let name = element.title.dropFirst(runningTitlePrefix.count)
            return name.isEmpty ? "a session is running" : "running: \(name)"
        }
        if element.role == "AXButton", element.description == stopResponseDescription {
            return "a reply is in progress"
        }
        return nil
    }
}
