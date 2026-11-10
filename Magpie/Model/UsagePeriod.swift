import Foundation

/// The time window the gateway tallies usage over (usage.Period).
nonisolated enum UsagePeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case week = "7d"
    case month = "30d"
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今天"
        case .week: "7 天"
        case .month: "30 天"
        case .all: "全部"
        }
    }
}

/// Days the reader picked (usage.Period "2026-10-01..2026-10-07"): whole days, both included, in
/// the calendar given. The gateway reads the dates in its own time zone and cuts a range of 2 to
/// 60 days into one point per day.
nonisolated struct DayRange: Hashable, Sendable {
    /// Midnight of the first day.
    var first: Date
    var count: Int
    var calendar: Calendar

    init(first: Date, count: Int, calendar: Calendar) {
        self.first = calendar.startOfDay(for: first)
        self.count = max(1, count)
        self.calendar = calendar
    }

    var last: Date { day(at: count - 1) }

    /// Midnight of every day, first to last.
    var days: [Date] { (0..<count).map(day(at:)) }

    /// The value for ?period=.
    var query: String {
        let style = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day()
        return "\(first.formatted(style))..\(last.formatted(style))"
    }

    /// Midnight of the day at index, 0 being the first.
    func day(at index: Int) -> Date {
        calendar.date(byAdding: .day, value: index, to: first) ?? first
    }
}
