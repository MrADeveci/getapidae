import XCTest
import IOKit.pwr_mgt
@testable import Apidae

final class SleepPreventerTests: XCTestCase {

    func testPreventSleepWithKeepDisplayAwakeUsesDisplayAssertion() {
        let preventer = SleepPreventer()
        defer { preventer.allowSleep() }

        preventer.preventSleep(keepDisplayAwake: true)

        XCTAssertEqual(
            preventer.activeAssertionType,
            kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
            "keepDisplayAwake=true should produce a PreventUserIdleDisplaySleep assertion"
        )
    }

    func testPreventSleepWithoutKeepDisplayAwakeUsesNoIdleSleepAssertion() {
        let preventer = SleepPreventer()
        defer { preventer.allowSleep() }

        preventer.preventSleep(keepDisplayAwake: false)

        XCTAssertEqual(
            preventer.activeAssertionType,
            kIOPMAssertionTypeNoIdleSleep as String,
            "keepDisplayAwake=false should produce a NoIdleSleep assertion"
        )
    }

    func testAllowSleepClearsActiveAssertionType() {
        let preventer = SleepPreventer()
        preventer.preventSleep(keepDisplayAwake: true)
        XCTAssertNotNil(preventer.activeAssertionType)

        preventer.allowSleep()

        XCTAssertNil(preventer.activeAssertionType, "allowSleep should clear the active assertion type")
    }
}
