import XCTest
@testable import Apidae

final class ClaudeActivityRulesTests: XCTestCase {

    func testSidebarRunningStatusGroupIsBusy() {
        let element = AXElementSummary(role: "AXGroup", subrole: "AXApplicationStatus", description: "Running")
        XCTAssertEqual(ClaudeActivityRules.busySignal(for: element), "a session is running")
    }

    func testSidebarRunningRowTitleIsBusyWithSessionName() {
        let element = AXElementSummary(role: "AXButton", title: "Running Apidae app updates")
        XCTAssertEqual(ClaudeActivityRules.busySignal(for: element), "running: Apidae app updates")
    }

    func testComposerStopResponseButtonIsBusy() {
        let element = AXElementSummary(role: "AXButton", description: "Stop response")
        XCTAssertEqual(ClaudeActivityRules.busySignal(for: element), "a reply is in progress")
    }

    func testIdleSidebarRowIsNotBusy() {
        let button = AXElementSummary(role: "AXButton", title: "Idle Autobiography")
        let image = AXElementSummary(role: "AXImage", description: "Idle")
        XCTAssertNil(ClaudeActivityRules.busySignal(for: button))
        XCTAssertNil(ClaudeActivityRules.busySignal(for: image))
    }

    func testEmptyApplicationStatusGroupIsNotBusy() {
        // Chat bubbles carry AXApplicationStatus groups with no description; they must not count.
        let element = AXElementSummary(role: "AXGroup", subrole: "AXApplicationStatus")
        XCTAssertNil(ClaudeActivityRules.busySignal(for: element))
    }

    func testRunningTextInsideMessageBodyIsNotBusy() {
        let text = AXElementSummary(role: "AXStaticText", value: "Running command…")
        let button = AXElementSummary(role: "AXButton", title: "Running command")
        XCTAssertNil(ClaudeActivityRules.busySignal(for: text))
        XCTAssertEqual(ClaudeActivityRules.busySignal(for: button), "running: command",
                       "a button titled 'Running …' is accepted; the sidebar row is the same shape")
    }

    func testSendButtonIsNotBusy() {
        let element = AXElementSummary(role: "AXButton", description: "Send message")
        XCTAssertNil(ClaudeActivityRules.busySignal(for: element))
    }
}
