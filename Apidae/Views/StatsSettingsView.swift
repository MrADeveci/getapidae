import SwiftUI
import Charts

struct StatsSettingsView: View {
    let statsService: StatsService?

    @State private var today: TodaySummary?
    @State private var week: [DaySummary] = []
    @State private var allTime: AllTimeTotals?
    @State private var recent: [RecentEvent] = []
    @State private var showClearConfirm = false

    var body: some View {
        Group {
            if let service = statsService {
                content(service: service)
            } else {
                UnavailableView()
            }
        }
    }

    @ViewBuilder
    private func content(service: StatsService) -> some View {
        Form {
            Section("Today") {
                TodaySection(summary: today)
            }
            Section("This week") {
                WeekChartSection(days: week)
            }
            Section("All-time") {
                AllTimeSection(totals: allTime)
            }
            Section("Recent activity") {
                RecentActivitySection(events: recent)
            }
            Section {
                Button("Clear stats history…", role: .destructive) {
                    showClearConfirm = true
                }
            }
        }
        .formStyle(.grouped)
        .task { await reload(service: service) }
        .onReceive(NotificationCenter.default.publisher(for: .apidaeStatsDidChange)) { _ in
            Task { await reload(service: service) }
        }
        .confirmationDialog(
            "Clear all stats history?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task { try? await service.clearAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all recorded lock and unlock events. This cannot be undone.")
        }
    }

    private func reload(service: StatsService) async {
        async let t = try? await service.todaySummary()
        async let w = try? await service.weekSummary()
        async let a = try? await service.allTimeTotals()
        async let r = try? await service.recentEvents(limit: 20)
        let (todayR, weekR, allR, recentR) = await (t, w, a, r)
        today = todayR ?? nil
        week = weekR ?? []
        allTime = allR ?? nil
        recent = recentR ?? []
    }
}

// MARK: - Today

private struct TodaySection: View {
    let summary: TodaySummary?

    var body: some View {
        if let s = summary, s.lockCount > 0 || s.isCurrentlyLocked {
            LabeledContent("Locks today") { Text("\(s.lockCount)") }
            LabeledContent("Time locked") {
                Text(StatsFormatters.shortDuration(s.totalDuration))
                    .monospacedDigit()
            }
            if s.isCurrentlyLocked {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Locked now")
                        .font(.callout)
                    Spacer()
                }
            }
        } else {
            Text("No locks today yet")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Week chart

private struct WeekChartSection: View {
    let days: [DaySummary]

    private var allZero: Bool { days.allSatisfy { $0.totalDuration == 0 } }

    /// Switch to hours when any day's total exceeds 60 minutes.
    private var useHours: Bool { days.contains { $0.totalDuration > 60 * 60 } }

    private var unitLabel: String { useHours ? "Hours" : "Minutes" }

    private func yValue(_ duration: TimeInterval) -> Double {
        useHours ? duration / 3600 : duration / 60
    }

    var body: some View {
        if days.isEmpty || allZero {
            Text("No activity this week")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Chart(days, id: \.date) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value(unitLabel, yValue(day.totalDuration))
                )
                .foregroundStyle(Color("ApidaeHoney"))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - All-time

private struct AllTimeSection: View {
    let totals: AllTimeTotals?

    var body: some View {
        if let t = totals, t.lockCount > 0 {
            LabeledContent("Total locks") { Text("\(t.lockCount)") }
            LabeledContent("Time locked") {
                Text(StatsFormatters.longDuration(t.totalDuration))
            }
            if let longest = t.longestLock {
                LabeledContent("Longest") {
                    Text("\(StatsFormatters.shortDuration(longest.duration)) on \(StatsFormatters.absoluteDate(longest.startDate))")
                        .multilineTextAlignment(.trailing)
                }
            }
        } else {
            Text("Start using Apidae to see your stats.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Recent activity

private struct RecentActivitySection: View {
    let events: [RecentEvent]

    private var newestFirst: [RecentEvent] { Array(events.reversed()) }

    var body: some View {
        if events.isEmpty {
            Text("No recent activity")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(newestFirst) { event in
                RecentActivityRow(event: event)
            }
        }
    }
}

private struct RecentActivityRow: View {
    let event: RecentEvent

    private var isLock: Bool { event.eventType == .lock }

    private var primaryText: String {
        if isLock {
            return "Locked · \(StatsFormatters.triggerDisplay(event.triggerMethod))"
        } else {
            if let dur = event.durationSeconds {
                return "Unlocked · \(StatsFormatters.shortDuration(dur))"
            }
            return "Unlocked"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isLock ? "lock.fill" : "lock.open.fill")
                .foregroundStyle(isLock ? Color("ApidaeHoney") : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText)
                    .font(.callout)
                Text(StatsFormatters.eventTimestamp(event.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Unavailable fallback

private struct UnavailableView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Stats unavailable on this device")
                .font(.headline)
            Text("Apidae couldn't access local storage to record lock and unlock events.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Formatters

private enum StatsFormatters {
    /// "23 min", "1h 14m"
    static func shortDuration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s == 0 { return "0 min" }
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = s >= 3600 ? [.hour, .minute] : [.minute]
        f.zeroFormattingBehavior = .dropAll
        return f.string(from: TimeInterval(s)) ?? "\(s/60) min"
    }

    /// "12 days, 4 hours" — long form for all-time totals.
    static func longDuration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s == 0 { return "0 minutes" }
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.maximumUnitCount = 2
        f.allowedUnits = [.day, .hour, .minute]
        f.zeroFormattingBehavior = .dropLeading
        return f.string(from: TimeInterval(s)) ?? "\(s/60) minutes"
    }

    private static let absoluteDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// "14 May 2026"
    static func absoluteDate(_ date: Date) -> String {
        absoluteDateFormatter.string(from: date)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static let absoluteEventFormatter: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true   // "Yesterday", "Today"
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Relative ("3 min ago") for the last 24 hours; absolute ("Yesterday 14:32",
    /// "14 May 14:32") for older events.
    static func eventTimestamp(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 24 * 3600 && interval >= 0 {
            return relativeFormatter.localizedString(for: date, relativeTo: now)
        }
        return absoluteEventFormatter.string(from: date)
    }

    /// Human-friendly label for the TriggerMethod cases.
    static func triggerDisplay(_ trigger: TriggerMethod) -> String {
        switch trigger {
        case .hotkey:         return "Hotkey"
        case .menu:           return "Menu bar"
        case .urlScheme:      return "URL scheme"
        case .settingsButton: return "Settings"
        case .touchID:        return "Touch ID"
        case .password:       return "Password"
        case .force:          return "Forced"
        case .unknown:        return "Unknown"
        }
    }
}
