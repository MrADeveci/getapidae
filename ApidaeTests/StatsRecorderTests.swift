import XCTest
@testable import Apidae

final class StatsRecorderTests: XCTestCase {

    // MARK: - Schema

    func testInitCreatesEmptyEventStore() async throws {
        let recorder = try StatsRecorder(location: .memory)
        let events = try await recorder.allEvents()
        XCTAssertEqual(events, [])
    }

    // MARK: - Recording

    func testRecordLockInsertsRowWithNilDuration() async throws {
        let recorder = try StatsRecorder(location: .memory)
        let when = Date(timeIntervalSince1970: 1_700_000_000)

        try await recorder.recordLock(trigger: .hotkey, at: when)
        let events = try await recorder.allEvents()

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.eventType, .lock)
        XCTAssertEqual(event.triggerMethod, .hotkey)
        XCTAssertNil(event.durationSeconds)
        XCTAssertEqual(event.timestamp.timeIntervalSince1970, 1_700_000_000, accuracy: 0.0001)
    }

    func testRecordUnlockInsertsRowWithDuration() async throws {
        let recorder = try StatsRecorder(location: .memory)
        let when = Date(timeIntervalSince1970: 1_700_000_120)

        try await recorder.recordUnlock(trigger: .touchID, durationSeconds: 120, at: when)
        let events = try await recorder.allEvents()

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.eventType, .unlock)
        XCTAssertEqual(event.triggerMethod, .touchID)
        XCTAssertEqual(event.durationSeconds, 120)
    }

    func testMultipleEventsPreserveChronologicalOrder() async throws {
        let recorder = try StatsRecorder(location: .memory)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        try await recorder.recordLock(trigger: .menu, at: t0)
        try await recorder.recordUnlock(trigger: .password, durationSeconds: 60, at: t0.addingTimeInterval(60))
        try await recorder.recordLock(trigger: .urlScheme, at: t0.addingTimeInterval(120))

        let events = try await recorder.allEvents()
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.map(\.eventType), [.lock, .unlock, .lock])
        XCTAssertEqual(events.map(\.triggerMethod), [.menu, .password, .urlScheme])
        XCTAssertTrue(events[0].id < events[1].id && events[1].id < events[2].id)
    }

    // MARK: - TriggerMethod round-trip

    func testEveryTriggerMethodRoundTrips() async throws {
        let recorder = try StatsRecorder(location: .memory)
        let triggers: [TriggerMethod] = [
            .hotkey, .menu, .urlScheme, .settingsButton,
            .touchID, .password, .force, .unknown
        ]
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        for (i, trigger) in triggers.enumerated() {
            try await recorder.recordLock(trigger: trigger, at: base.addingTimeInterval(TimeInterval(i)))
        }

        let events = try await recorder.allEvents()
        XCTAssertEqual(events.map(\.triggerMethod), triggers)
    }

    // MARK: - Delete

    func testDeleteAllRemovesAllRows() async throws {
        let recorder = try StatsRecorder(location: .memory)
        let when = Date()
        try await recorder.recordLock(trigger: .hotkey, at: when)
        try await recorder.recordUnlock(trigger: .hotkey, durationSeconds: 30, at: when.addingTimeInterval(30))
        let beforeCount = try await recorder.allEvents().count
        XCTAssertEqual(beforeCount, 2)

        try await recorder.deleteAll()
        let after = try await recorder.allEvents()
        XCTAssertEqual(after, [])
    }

    // MARK: - File-backed persistence

    func testEventsPersistAcrossRecorderInstancesOnSameFile() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("apidae-stats-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tmp) }

        do {
            let recorder = try StatsRecorder(location: .file(tmp))
            try await recorder.recordLock(trigger: .menu, at: Date(timeIntervalSince1970: 1_700_000_000))
        }

        let recorder = try StatsRecorder(location: .file(tmp))
        let events = try await recorder.allEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.triggerMethod, .menu)
    }
}
