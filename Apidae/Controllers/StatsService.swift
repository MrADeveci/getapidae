import Foundation
import os.log

private let logger = Logger(subsystem: "app.getapidae.mac", category: "StatsService")

struct TodaySummary: Sendable, Equatable {
    let lockCount: Int
    let totalDuration: TimeInterval
    let isCurrentlyLocked: Bool
}

struct DaySummary: Sendable, Equatable {
    let date: Date
    let lockCount: Int
    let totalDuration: TimeInterval
}

struct LongestLock: Sendable, Equatable {
    let duration: TimeInterval
    let startDate: Date
}

struct AllTimeTotals: Sendable, Equatable {
    let lockCount: Int
    let totalDuration: TimeInterval
    let longestLock: LongestLock?
}

struct RecentEvent: Sendable, Equatable {
    let timestamp: Date
    let eventType: EventType
    let triggerMethod: TriggerMethod
    let durationSeconds: TimeInterval?
}

/// Cancels its task when the owning actor is deallocated. Actors can't reference
/// isolated state from `deinit`, so the task handle lives in this side-car box.
private final class CancellationBox: @unchecked Sendable {
    var task: Task<Void, Never>?
    deinit { task?.cancel() }
}

actor StatsService {
    private let recorder: StatsRecorder
    private let calendar: Calendar

    private var cachedWeek: (data: [DaySummary], at: Date)?
    private var cachedAllTime: (data: AllTimeTotals, at: Date)?

    private let observerBox = CancellationBox()

    /// Safety net so a missed notification doesn't leave stale data indefinitely.
    private static let cacheTTL: TimeInterval = 5 * 60

    init(recorder: StatsRecorder, calendar: Calendar = .current) {
        self.recorder = recorder
        self.calendar = calendar
        let box = self.observerBox
        box.task = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .apidaeStatsDidChange) {
                if Task.isCancelled { return }
                await self?.invalidateCache()
            }
        }
    }

    // MARK: - Public API

    /// Lock count, time-locked, and live-locked flag for "today" in the service's calendar.
    /// Always hits the DB so the Stats tab reflects the lock that just happened.
    func todaySummary(now: Date = Date()) async throws -> TodaySummary {
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return TodaySummary(lockCount: 0, totalDuration: 0, isCurrentlyLocked: false)
        }

        let allEvents = try await recorder.allEvents()

        var lockCount = 0
        var totalDuration: TimeInterval = 0
        for event in allEvents {
            switch event.eventType {
            case .lock:
                if event.timestamp >= startOfDay && event.timestamp < endOfDay {
                    lockCount += 1
                }
            case .unlock:
                guard let dur = event.durationSeconds else { continue }
                // Duration is attributed to the day the lock STARTED.
                let lockStart = event.timestamp.addingTimeInterval(-dur)
                if lockStart >= startOfDay && lockStart < endOfDay {
                    totalDuration += dur
                }
            }
        }
        let isCurrentlyLocked = allEvents.last?.eventType == .lock
        return TodaySummary(lockCount: lockCount, totalDuration: totalDuration, isCurrentlyLocked: isCurrentlyLocked)
    }

    /// Last 7 days oldest-first, including empty days. Locks that cross midnight
    /// have their full duration attributed to the day the lock started.
    func weekSummary(now: Date = Date()) async throws -> [DaySummary] {
        if let cached = cachedWeek, Date().timeIntervalSince(cached.at) < Self.cacheTTL {
            return cached.data
        }

        let today = calendar.startOfDay(for: now)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today),
              let weekEnd = calendar.date(byAdding: .day, value: 1, to: today) else {
            return []
        }

        var buckets: [Date: (lockCount: Int, duration: TimeInterval)] = [:]
        for offset in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: weekStart) {
                buckets[day] = (0, 0)
            }
        }

        let allEvents = try await recorder.allEvents()
        for event in allEvents {
            switch event.eventType {
            case .lock:
                let day = calendar.startOfDay(for: event.timestamp)
                guard day >= weekStart && day < weekEnd else { continue }
                buckets[day]?.lockCount += 1
            case .unlock:
                guard let dur = event.durationSeconds else { continue }
                let lockStart = event.timestamp.addingTimeInterval(-dur)
                let day = calendar.startOfDay(for: lockStart)
                guard day >= weekStart && day < weekEnd else { continue }
                buckets[day]?.duration += dur
            }
        }

        let summaries = buckets.keys.sorted().map { key -> DaySummary in
            let b = buckets[key] ?? (0, 0)
            return DaySummary(date: key, lockCount: b.lockCount, totalDuration: b.duration)
        }
        cachedWeek = (summaries, Date())
        return summaries
    }

    func allTimeTotals() async throws -> AllTimeTotals {
        if let cached = cachedAllTime, Date().timeIntervalSince(cached.at) < Self.cacheTTL {
            return cached.data
        }

        let events = try await recorder.allEvents()
        var lockCount = 0
        var totalDuration: TimeInterval = 0
        var longest: LongestLock?
        for event in events {
            switch event.eventType {
            case .lock:
                lockCount += 1
            case .unlock:
                guard let dur = event.durationSeconds else { continue }
                totalDuration += dur
                if dur > (longest?.duration ?? -1) {
                    longest = LongestLock(duration: dur, startDate: event.timestamp.addingTimeInterval(-dur))
                }
            }
        }
        let totals = AllTimeTotals(lockCount: lockCount, totalDuration: totalDuration, longestLock: longest)
        cachedAllTime = (totals, Date())
        return totals
    }

    /// Last `limit` events oldest-first.
    func recentEvents(limit: Int) async throws -> [RecentEvent] {
        guard limit > 0 else { return [] }
        let events = try await recorder.allEvents()
        return events.suffix(limit).map {
            RecentEvent(
                timestamp: $0.timestamp,
                eventType: $0.eventType,
                triggerMethod: $0.triggerMethod,
                durationSeconds: $0.durationSeconds
            )
        }
    }

    // MARK: - Internal (tests)

    func invalidateCache() {
        cachedWeek = nil
        cachedAllTime = nil
    }
}
