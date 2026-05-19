import XCTest
@testable import Apidae

final class StatsServiceTests: XCTestCase {

    // Fixed calendar so tests don't depend on the machine's timezone.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // MARK: - Helpers

    private func makeRecorder() throws -> StatsRecorder {
        try StatsRecorder(location: .memory)
    }

    private func makeService(recorder: StatsRecorder) -> StatsService {
        StatsService(recorder: recorder, calendar: calendar)
    }

    /// 2026-05-15 12:00:00 UTC — fixed test "now".
    private let now = Date(timeIntervalSince1970: 1_778_932_800)

    /// Seed a lock/unlock pair starting `secondsAgo` before `now`, lasting `duration`.
    private func seedLockUnlock(
        _ recorder: StatsRecorder,
        startingBeforeNow secondsAgo: TimeInterval,
        duration: TimeInterval,
        trigger: TriggerMethod = .hotkey
    ) async throws {
        let start = now.addingTimeInterval(-secondsAgo)
        let end = start.addingTimeInterval(duration)
        try await recorder.recordLock(trigger: trigger, at: start)
        try await recorder.recordUnlock(trigger: trigger, durationSeconds: duration, at: end)
    }

    // MARK: - todaySummary

    func testTodaySummaryEmptyDatabase() async throws {
        let recorder = try makeRecorder()
        let service = makeService(recorder: recorder)
        let summary = try await service.todaySummary(now: now)
        XCTAssertEqual(summary, TodaySummary(lockCount: 0, totalDuration: 0, isCurrentlyLocked: false))
    }

    func testTodaySummaryCountsTodayLocksAndDuration() async throws {
        let recorder = try makeRecorder()
        let service = makeService(recorder: recorder)
        // Two locks today: 5 min and 30 min.
        try await seedLockUnlock(recorder, startingBeforeNow: 60 * 60,      duration: 30 * 60)
        try await seedLockUnlock(recorder, startingBeforeNow: 10 * 60,      duration: 5 * 60)
        // One lock yesterday should be excluded.
        try await seedLockUnlock(recorder, startingBeforeNow: 30 * 60 * 60, duration: 60)

        let summary = try await service.todaySummary(now: now)
        XCTAssertEqual(summary.lockCount, 2)
        XCTAssertEqual(summary.totalDuration, (30 + 5) * 60, accuracy: 0.0001)
        XCTAssertFalse(summary.isCurrentlyLocked)
    }

    func testTodaySummaryIsCurrentlyLockedWhenLastEventIsLock() async throws {
        let recorder = try makeRecorder()
        let service = makeService(recorder: recorder)
        try await recorder.recordLock(trigger: .menu, at: now.addingTimeInterval(-30))
        let summary = try await service.todaySummary(now: now)
        XCTAssertEqual(summary.lockCount, 1)
        XCTAssertEqual(summary.totalDuration, 0)
        XCTAssertTrue(summary.isCurrentlyLocked)
    }

    // MARK: - weekSummary

    func testWeekSummaryReturnsSevenChronologicalDays() async throws {
        let recorder = try makeRecorder()
        let service = makeService(recorder: recorder)
        let week = try await service.weekSummary(now: now)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week, week.sorted(by: { $0.date < $1.date }))
        // Week should end on today's start-of-day.
        XCTAssertEqual(week.last?.date, calendar.startOfDay(for: now))
    }

    func testWeekSummaryBucketsByLockStartDay() async throws {
        let recorder = try makeRecorder()
        let service = makeService(recorder: recorder)
        // Today: one 10-min lock.
        try await seedLockUnlock(recorder, startingBeforeNow: 60 * 60, duration: 10 * 60)
        // 3 days ago: two locks (15 + 5 minutes).
        try await seedLockUnlock(recorder, startingBeforeNow: 3 * 86_400 + 3600, duration: 15 * 60)
        try await seedLockUnlock(recorder, startingBeforeNow: 3 * 86_400 + 60,   duration: 5 * 60)
        // 30 days ago: should be ignored.
        try await seedLockUnlock(recorder, startingBeforeNow: 30 * 86_400, duration: 60)

        let week = try await service.weekSummary(now: now)
        let today = calendar.startOfDay(for: now)
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!

        let todayBucket = try XCTUnwrap(week.first { $0.date == today })
        XCTAssertEqual(todayBucket.lockCount, 1)
        XCTAssertEqual(todayBucket.totalDuration, 10 * 60, accuracy: 0.0001)

        let threeAgo = try XCTUnwrap(week.first { $0.date == threeDaysAgo })
        XCTAssertEqual(threeAgo.lockCount, 2)
        XCTAssertEqual(threeAgo.totalDuration, 20 * 60, accuracy: 0.0001)
    }

    /// A lock that crosses midnight has its full duration attributed to the day it started.
    func testWeekSummaryAttributesMidnightCrossingLockToStartDay() async throws {
        let recorder = try makeRecorder()
        let service = makeService(recorder: recorder)

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        // Lock at 23:30 yesterday, unlock at 00:30 today (60 min spanning midnight).
        let lockStart = yesterday.addingTimeInterval(23 * 3600 + 30 * 60)
        let unlockAt = lockStart.addingTimeInterval(60 * 60)
        try await recorder.recordLock(trigger: .hotkey, at: lockStart)
        try await recorder.recordUnlock(trigger: .hotkey, durationSeconds: 60 * 60, at: unlockAt)

        let week = try await service.weekSummary(now: now)
        let yesterdayBucket = try XCTUnwrap(week.first { $0.date == yesterday })
        let todayBucket = try XCTUnwrap(week.first { $0.date == today })

        XCTAssertEqual(yesterdayBucket.lockCount, 1)
        XCTAssertEqual(yesterdayBucket.totalDuration, 60 * 60, accuracy: 0.0001,
                       "Full duration should be attributed to the start day, not split")
        XCTAssertEqual(todayBucket.lockCount, 0)
        XCTAssertEqual(todayBucket.totalDuration, 0)
    }

    // MARK: - allTimeTotals

    func testAllTimeTotalsEmpty() async throws {
        let recorder = try makeRecorder()
        let service = makeService(recorder: recorder)
        let totals = try await service.allTimeTotals()
        XCTAssertEqual(totals, AllTimeTotals(lockCount: 0, totalDuration: 0, longestLock: nil))
    }

    func testAllTimeTotalsIncludesLongestLock() async throws {
        let recorder = try makeRecorder()
        let service = makeService(recorder: recorder)
        try await seedLockUnlock(recorder, startingBeforeNow: 86_400 * 2, duration: 5 * 60)
        try await seedLockUnlock(recorder, startingBeforeNow: 86_400,     duration: 45 * 60)
        try await seedLockUnlock(recorder, startingBeforeNow: 3600,       duration: 10 * 60)

        let totals = try await service.allTimeTotals()
        XCTAssertEqual(totals.lockCount, 3)
        XCTAssertEqual(totals.totalDuration, (5 + 45 + 10) * 60, accuracy: 0.0001)
        let longest = try XCTUnwrap(totals.longestLock)
        XCTAssertEqual(longest.duration, 45 * 60, accuracy: 0.0001)
        // The 45-min lock started 86_400 seconds before now.
        XCTAssertEqual(longest.startDate.timeIntervalSince1970,
                       now.addingTimeInterval(-86_400).timeIntervalSince1970,
                       accuracy: 0.0001)
    }

    // MARK: - recentEvents

    func testRecentEventsReturnsEmptyWhenLimitIsZero() async throws {
        let recorder = try makeRecorder()
        let service = makeService(recorder: recorder)
        try await seedLockUnlock(recorder, startingBeforeNow: 60, duration: 30)
        let events = try await service.recentEvents(limit: 0)
        XCTAssertEqual(events, [])
    }

    func testRecentEventsReturnsLastNChronologically() async throws {
        let recorder = try makeRecorder()
        let service = makeService(recorder: recorder)
        // Three lock/unlock pairs, total 6 events.
        try await seedLockUnlock(recorder, startingBeforeNow: 3 * 3600, duration: 60)
        try await seedLockUnlock(recorder, startingBeforeNow: 2 * 3600, duration: 60)
        try await seedLockUnlock(recorder, startingBeforeNow: 1 * 3600, duration: 60)

        let recent = try await service.recentEvents(limit: 4)
        XCTAssertEqual(recent.count, 4)
        // Must be sorted oldest first.
        XCTAssertEqual(recent, recent.sorted(by: { $0.timestamp < $1.timestamp }))
        // The last event in the list is the most recent unlock.
        XCTAssertEqual(recent.last?.eventType, .unlock)
        XCTAssertEqual(recent.last?.durationSeconds, 60)
    }

    // MARK: - Cache invalidation (push-driven via NotificationCenter)

    func testAllTimeTotalsCacheInvalidatesWhenRecorderInsertsEvent() async throws {
        let recorder = try makeRecorder()
        let service = makeService(recorder: recorder)

        try await seedLockUnlock(recorder, startingBeforeNow: 3600, duration: 60)
        let first = try await service.allTimeTotals()
        XCTAssertEqual(first.lockCount, 1)
        XCTAssertEqual(first.totalDuration, 60, accuracy: 0.0001)

        try await seedLockUnlock(recorder, startingBeforeNow: 120, duration: 90)

        // Notification delivery to the actor's observer task is async; poll the public
        // API until the cache reflects the new event, with a hard timeout.
        let updated = try await pollUntilTotals(service: service, lockCount: 2)
        XCTAssertEqual(updated.lockCount, 2)
        XCTAssertEqual(updated.totalDuration, 150, accuracy: 0.0001,
                       "Second call must reflect the newly-recorded event, not the cached totals")
    }

    private func pollUntilTotals(
        service: StatsService,
        lockCount expected: Int,
        timeout: TimeInterval = 1.0
    ) async throws -> AllTimeTotals {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let totals = try await service.allTimeTotals()
            if totals.lockCount == expected { return totals }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("allTimeTotals never reflected lockCount=\(expected) within \(timeout)s")
        return try await service.allTimeTotals()
    }
}
