import Foundation
import IOKit.pwr_mgt
import os.log

private let logger = Logger(subsystem: "app.getapidae.mac", category: "SleepPreventer")

class SleepPreventer {
    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var isActive = false
    private(set) var activeAssertionType: String?

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
            ? "Apidae: hive closed — preventing display and idle sleep"
            : "Apidae: hive closed — preventing idle sleep"
        let result = IOPMAssertionCreateWithName(
            assertionType as NSString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as NSString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isActive = true
            activeAssertionType = assertionType
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

    deinit { allowSleep() }
}
