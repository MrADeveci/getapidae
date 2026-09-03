import Foundation

/// Pure decision logic for the keep-awake controller: given what the providers just
/// reported, should Apidae be holding a power assertion right now?
///
/// The grace period stops the assertion flapping between tool calls: a provider that
/// was busy a moment ago and now looks idle is still treated as busy until
/// `grace` seconds have passed without a busy reading.
enum KeepAwakeDecider {
    static func shouldHold(
        activities: [ProviderActivity],
        currentlyHolding: Bool,
        lastBusyAt: Date?,
        now: Date,
        grace: TimeInterval
    ) -> Bool {
        if activities.contains(where: { $0.isBusy }) { return true }
        guard currentlyHolding, let lastBusyAt else { return false }
        return now.timeIntervalSince(lastBusyAt) < grace
    }

    /// The first busy detail across providers, if any, for display.
    static func busyDetail(activities: [ProviderActivity]) -> String? {
        for activity in activities {
            if case .busy(let detail) = activity { return detail }
        }
        return nil
    }
}
