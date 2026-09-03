import Foundation
import Combine
import AppKit
import os.log

private let logger = Logger(subsystem: "app.getapidae.mac", category: "KeepAwakeController")

/// What the keep-awake watcher is doing, for the menu and settings.
enum KeepAwakeState: Equatable {
    /// The user switched the feature off.
    case disabled
    /// Accessibility permission is missing, so providers cannot be inspected.
    case needsAccessibility
    /// Watching, nothing busy: carries the latest reading per provider name.
    case watching([String: ProviderActivity])
    /// Holding a power assertion because a provider is (or was just) busy.
    case holding(since: Date, detail: String)

    var isHolding: Bool {
        if case .holding = self { return true }
        return false
    }
}

/// Polls the activity providers and holds a power assertion while any of them is
/// working, so the Mac cannot idle-sleep under a running agent even when nobody
/// pressed the lock key. This is independent of the lock overlay: both may hold an
/// assertion at once and IOKit simply keeps the machine awake until both let go.
///
/// Timing lives in `Constants.Timing`: `keepAwakePollInterval` between checks and
/// `keepAwakeIdleGrace` before an idle-looking provider releases the hold.
@MainActor
final class KeepAwakeController: ObservableObject {
    static let enabledKey = "keepAwakeEnabled"
    static let keepDisplayOnKey = "keepAwakeKeepDisplayOn"

    @Published private(set) var state: KeepAwakeState = .disabled
    @Published private(set) var lastChecked: Date?
    @Published private(set) var holdElapsed: TimeInterval = 0

    let providers: [any ActivityProvider]

    private let sleepPreventer = SleepPreventer(label: "keeping the hive awake")
    private var timer: Timer?
    private var defaultsObserver: Any?
    private var lastBusyAt: Date?
    private var holdingSince: Date?
    private var checkInFlight = false

    var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) ?? true
    }

    var keepDisplayOn: Bool {
        (UserDefaults.standard.object(forKey: Self.keepDisplayOnKey) as? Bool) ?? false
    }

    init(providers: [any ActivityProvider]) {
        self.providers = providers

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }

        timer = Timer.scheduledTimer(withTimeInterval: Constants.Timing.keepAwakePollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        tick()
    }

    deinit {
        timer?.invalidate()
        if let obs = defaultsObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - Polling

    private func tick() {
        guard isEnabled else {
            if holdingSince != nil { release(reason: "disabled") }
            if state != .disabled { state = .disabled }
            return
        }
        guard AccessibilityChecker.isEnabled else {
            if holdingSince != nil { release(reason: "accessibility revoked") }
            if state != .needsAccessibility { state = .needsAccessibility }
            return
        }
        guard !checkInFlight else { return }
        checkInFlight = true

        let providers = self.providers
        Task.detached(priority: .utility) {
            let readings = providers.map { ($0.displayName, $0.checkActivity()) }
            await MainActor.run { [weak self] in
                self?.apply(readings)
            }
        }
    }

    private func apply(_ readings: [(String, ProviderActivity)]) {
        checkInFlight = false
        let now = Date()
        lastChecked = now
        let activities = readings.map { $0.1 }
        if activities.contains(where: { $0.isBusy }) { lastBusyAt = now }

        let hold = KeepAwakeDecider.shouldHold(
            activities: activities,
            currentlyHolding: holdingSince != nil,
            lastBusyAt: lastBusyAt,
            now: now,
            grace: Constants.Timing.keepAwakeIdleGrace
        )

        if hold {
            if holdingSince == nil {
                holdingSince = now
                sleepPreventer.preventSleep(keepDisplayAwake: keepDisplayOn)
                logger.notice("Holding: \(KeepAwakeDecider.busyDetail(activities: activities) ?? "busy", privacy: .public)")
            }
            sleepPreventer.nudgeUserActivityIfDue(now: now)
            holdElapsed = now.timeIntervalSince(holdingSince ?? now)
            let detail = KeepAwakeDecider.busyDetail(activities: activities) ?? "finishing up"
            state = .holding(since: holdingSince ?? now, detail: detail)
        } else {
            if holdingSince != nil { release(reason: "idle for \(Int(Constants.Timing.keepAwakeIdleGrace))s") }
            state = .watching(Dictionary(readings, uniquingKeysWith: { $1 }))
        }
    }

    private func release(reason: String) {
        sleepPreventer.allowSleep()
        holdingSince = nil
        holdElapsed = 0
        logger.notice("Released: \(reason, privacy: .public)")
    }
}
