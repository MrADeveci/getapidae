import Foundation
import IOKit.pwr_mgt
import os.log

private let logger = Logger(subsystem: "app.getapidae.mac", category: "SleepPreventer")

class SleepPreventer {
    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var isActive = false

    func preventSleep() {
        guard !isActive else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as NSString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Apidae: hive closed — preventing idle sleep" as NSString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isActive = true
            logger.notice("Created sleep assertion type=NoIdleSleepAssertion id=\(self.assertionID, privacy: .public) result=\(result, privacy: .public)")
        } else {
            logger.error("Failed to create sleep assertion type=NoIdleSleepAssertion result=\(result, privacy: .public)")
        }
    }

    func allowSleep() {
        guard isActive else { return }
        let releasedID = assertionID
        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            logger.notice("Released sleep assertion id=\(releasedID, privacy: .public) result=\(result, privacy: .public)")
        } else {
            logger.error("Failed to release sleep assertion id=\(releasedID, privacy: .public) result=\(result, privacy: .public)")
        }
        isActive = false
    }

    deinit { allowSleep() }
}
