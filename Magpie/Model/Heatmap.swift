import Foundation

/// The last 53 weeks a day each, as the web dashboard's heatmap lays them out (usage.Heatmap):
/// from the Monday 52 weeks before this week's through today.
/// The gateway serves /api/usage/heatmap only to its admin GUI, so a held key stitches the same
/// days together from picked ranges of /usage/requests, each at most 60 days so the gateway
/// answers with one point per day. Days split by the gateway's time zone, as the trend does; here
/// a day is named by the same calendar date on the phone.
nonisolated struct Heatmap: Hashable, Sendable {
    static let weeks = 53
    /// Past this many days a picked range comes back in week buckets instead of days.
    static let maxRangeDays = 60

    /// One day's calls (usage.Day).
    struct Day: Hashable, Identifiable, Sendable {
        /// Midnight of the day in the phone's calendar.
        var date: Date
        var totals: UsageTotals

        var id: Date { date }
    }

    /// Every day from the start Monday through today, oldest first.
    var days: [Day]
    var calendar: Calendar
    /// The sum over every day.
    var totals: UsageTotals

    init(days: [Day], calendar: Calendar) {
        self.days = days
        self.calendar = calendar
        totals = days.reduce(into: UsageTotals()) { $0.add($1.totals) }
    }

    /// Stitches the gateway's day points onto the ranges they were asked for, by position: a range
    /// of n days comes back as n points. A gateway too old to know picked ranges answers with its
    /// 30-day default instead, which the count gives away.
    init(ranges: [DayRange], series: [[SeriesPoint]], calendar: Calendar) throws(MagpieError) {
        var days: [Day] = []
        for (range, points) in zip(ranges, series) {
            guard points.count == range.count else {
                throw .decoding(
                    "\(range.query): expected \(range.count) day points, got \(points.count)")
            }
            for (date, point) in zip(range.days, points) {
                days.append(Day(date: date, totals: point.totals))
            }
        }
        self.init(days: days, calendar: calendar)
    }

    var hasCalls: Bool { totals.calls > 0 }

    /// Weeks on the grid; the last one is partial until Sunday.
    var weekCount: Int { (days.count + 6) / 7 }

    /// The Monday the heatmap starts on: this week's Monday, 52 weeks back.
    static func start(before today: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: today)
        let sinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -sinceMonday - 7 * (weeks - 1), to: day) ?? day
    }

    /// The picked ranges that together cover the start Monday through today: as few as fit in
    /// maxRangeDays each, near-equal and contiguous.
    static func ranges(through today: Date, calendar: Calendar) -> [DayRange] {
        let start = start(before: today, calendar: calendar)
        let end = calendar.startOfDay(for: today)
        let total = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let count = max(1, Int((Double(total) / Double(maxRangeDays)).rounded(.up)))
        var out: [DayRange] = []
        var offset = 0
        for index in 0..<count {
            let size = total / count + (index < total % count ? 1 : 0)
            let first = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            out.append(DayRange(first: first, count: size, calendar: calendar))
            offset += size
        }
        return out
    }

    /// Days that had a call.
    var activeDays: Int { days.count { $0.totals.calls > 0 } }

    /// How a date of the heatmap is written: in its calendar and that calendar's locale and zone.
    var dateStyle: Date.FormatStyle {
        Date.FormatStyle(
            locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// The month named above a week, by week index, as the web dashboard picks them: the week
    /// whose Monday begins a new month, unless the month is mostly gone in the first week (past
    /// the 14th) or the week is the last one, which has no room for a name.
    func monthLabels() -> [Int: String] {
        var labels: [Int: String] = [:]
        var month: Int?
        for week in 0..<weekCount {
            let monday = days[week * 7].date
            let thisMonth = calendar.component(.month, from: monday)
            guard thisMonth != month else { continue }
            month = thisMonth
            let mostlyGone = week == 0 && calendar.component(.day, from: monday) > 14
            if !mostlyGone, week < weekCount - 1 {
                labels[week] = monday.formatted(dateStyle.month(.abbreviated))
            }
        }
        return labels
    }
}

/// Grades a day 0 (none) to 4 by the quartiles of the days that had anything, as a calendar of
/// contributions does. Under eight such days a quartile is one day or none, so two days 2% apart
/// could be two shades apart and one twice another the same: then a day is graded by its share of
/// the busiest instead.
nonisolated struct HeatScale: Hashable, Sendable {
    /// The values above zero, smallest first.
    private let nonzero: [Double]

    init(values: [Double]) {
        nonzero = values.filter { $0 > 0 }.sorted()
    }

    func level(of value: Double) -> Int {
        guard value > 0, let top = nonzero.last else { return 0 }
        if nonzero.count < 8 {
            return min(4, max(1, Int((4 * value / top - 1e-9).rounded(.up))))
        }
        if value >= top { return 4 }
        if value <= quartile(0.25) { return 1 }
        if value <= quartile(0.5) { return 2 }
        if value <= quartile(0.75) { return 3 }
        return 4
    }

    private func quartile(_ fraction: Double) -> Double {
        nonzero[min(nonzero.count - 1, Int(fraction * Double(nonzero.count)))]
    }
}
