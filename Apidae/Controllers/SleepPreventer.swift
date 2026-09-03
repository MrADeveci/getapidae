import Foundation
import IOKit.pwr_mgt
import os.log

private let logger = Logger(subsystem: "app.getapidae.mac", category: "SleepPreventer")

class SleepPreventer {
    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var isActive = false
    private(set) var activeAssertionType: String?
    private var lastUserActivityNudge: Date = .distantPast
    private let label: String

    /// - Parameter label: short human-readable owner shown in `pmset -g assertions`
    ///   so a lock-session assertion and a keep-awake assertion can be told apart.
    init(label: String = "hive closed") {
        self.label = label
    }

    /// Holds a power assertion for the duration of a lock session.
    /// - Parameter keepDisplayAwake: when `true`, prevents both display and system idle sleep
    ///   (`PreventUserIdleDisplaySleep`); when `false`, prevents only system idle sleep
    ///   (`NoIdleSleep`) and the display may turn off after its idle timeout.
    func preventSleep(keepDisplayAwake: Bool) {
        guard !isActive else { return }
        let assertionType = keepDisplayAwake
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypeNoIdleSleep
        let reason = keepDisplayAwake
            ? "Apidae: \(label), preventing display and idle sleep"
            : "Apidae: \(label), preventing idle sleep"
        let result = IOPMAssertionCreateWithName(
            assertionType as NSString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as NSString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isActive = true
            activeAssertionType = assertionType
            lastUserActivityNudge = .distantPast
            logger.notice("Created sleep assertion type=\(assertionType, privacy: .public) id=\(self.assertionID, privacy: .public) result=\(result, privacy: .public)")
        } else {
            logger.error("Failed to create sleep assertion type=\(assertionType, privacy: .public) result=\(result, privacy: .public)")
        }
    }

    func allowSleep() {
        guard isActive else { return }
        let releasedID = assertionID
        let releasedType = activeAssertionType ?? "unknown"
        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            logger.notice("Released sleep assertion type=\(releasedType, privacy: .public) id=\(releasedID, privacy: .public) result=\(result, privacy: .public)")
        } else {
            logger.error("Failed to release sleep assertion type=\(releasedType, privacy: .public) id=\(releasedID, privacy: .public) result=\(result, privacy: .public)")
        }
        isActive = false
        activeAssertionType = nil
    }

    /// A `PreventUserIdleDisplaySleep` assertion stops the display sleeping, but it does
    /// not stop the screen saver or the "lock after screen saver" timer, and on some
    /// systems it does not stop the pre-sleep dim either. Declaring user activity does:
    /// it resets the idle clock exactly as a key press would. Call this from a periodic
    /// tick while the display must stay lit; it throttles itself to
    /// `Constants.Timing.userActivityNudgeInterval`.
    func nudgeUserActivityIfDue(now: Date = Date()) {
        guard isActive, activeAssertionType == kIOPMAssertionTypePreventUserIdleDisplaySleep as String else { return }
        guard now.timeIntervalSince(lastUserActivityNudge) >= Constants.Timing.userActivityNudgeInterval else { return }
        lastUserActivityNudge = now
        var activityID = IOPMAssertionID(0)
        let result = IOPMAssertionDeclareUserActivity(
            "Apidae: \(label), keeping the display lit" as NSString,
            kIOPMUserActiveLocal,
            &activityID
        )
        if result == kIOReturnSuccess {
            logger.debug("Declared user activity id=\(activityID, privacy: .public)")
        } else {
            logger.error("Failed to declare user activity result=\(result, privacy: .public)")
        }
    }

    deinit { allowSleep() }
}
