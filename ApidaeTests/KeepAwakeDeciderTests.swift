import XCTest
@testable import Apidae

final class KeepAwakeDeciderTests: XCTestCase {
    private let grace: TimeInterval = 90
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testBusyProviderHolds() {
        XCTAssertTrue(KeepAwakeDecider.shouldHold(
            activities: [.busy(detail: "x")], currentlyHolding: false, lastBusyAt: nil, now: now, grace: grace))
    }

    func testIdleProviderWithNoHistoryDoesNotHold() {
        XCTAssertFalse(KeepAwakeDecider.shouldHold(
            activities: [.idle], currentlyHolding: false, lastBusyAt: nil, now: now, grace: grace))
    }

    func testNotRunningDoesNotHold() {
        XCTAssertFalse(KeepAwakeDecider.shouldHold(
            activities: [.notRunning], currentlyHolding: false, lastBusyAt: nil, now: now, grace: grace))
    }

    func testIdleInsideGraceKeepsHolding() {
        XCTAssertTrue(KeepAwakeDecider.shouldHold(
            activities: [.idle], currentlyHolding: true, lastBusyAt: now.addingTimeInterval(-30), now: now, grace: grace))
    }

    func testIdleBeyondGraceReleases() {
        XCTAssertFalse(KeepAwakeDecider.shouldHold(
            activities: [.idle], currentlyHolding: true, lastBusyAt: now.addingTimeInterval(-91), now: now, grace: grace))
    }

    func testGraceDoesNotApplyWhenNotHolding() {
        // A stale busy timestamp from a previous hold must not start a new one.
        XCTAssertFalse(KeepAwakeDecider.shouldHold(
            activities: [.idle], currentlyHolding: false, lastBusyAt: now.addingTimeInterval(-10), now: now, grace: grace))
    }

    func testAnyBusyProviderAmongSeveralHolds() {
        XCTAssertTrue(KeepAwakeDecider.shouldHold(
            activities: [.notRunning, .idle, .busy(detail: "y")], currentlyHolding: false, lastBusyAt: nil, now: now, grace: grace))
    }

    func testBusyDetailPicksFirstBusy() {
        XCTAssertEqual(KeepAwakeDecider.busyDetail(activities: [.idle, .busy(detail: "first"), .busy(detail: "second")]), "first")
        XCTAssertNil(KeepAwakeDecider.busyDetail(activities: [.idle, .notRunning]))
    }
}
