import Foundation
import Testing

@testable import Magpie

nonisolated private func calendar(in zone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}

nonisolated private let utc = calendar(in: .gmt)
nonisolated private let dayStyle = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()

/// Midnight UTC of a day written 2026-11-10.
nonisolated private func day(_ text: String) throws -> Date {
    try Date(text, strategy: dayStyle)
}

private func dayPoints(calls: [Int]) throws -> [SeriesPoint] {
    let json = "[" + calls.map { #"{"label":"d","calls":\#($0)}"# }.joined(separator: ",") + "]"
    return try MagpieJSON.decoder().decode([SeriesPoint].self, from: Data(json.utf8))
}

/// Every day from the heatmap's start through today, none with calls.
private func emptyYear(through today: String) throws -> Heatmap {
    let ranges = Heatmap.ranges(through: try day(today), calendar: utc)
    let days = ranges.flatMap(\.days).map { Heatmap.Day(date: $0, totals: UsageTotals()) }
    return Heatmap(days: days, calendar: utc)
}

/// Answers a picked range of /usage/requests the way the gateway does, with one point per day;
/// each day's call count is its day of the month, so a point stitched onto the wrong date shows.
private actor DayPointGateway: Transport {
    private(set) var queries: [[String: String]] = []

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url,
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            throw URLError(.badURL)
        }
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        queries.append(query)
        let ends = try (query["period"] ?? "").components(separatedBy: "..").map(day)
        guard ends.count == 2 else {
            throw URLError(.badURL)
        }
        var points: [String] = []
        var date = ends[0]
        while date <= ends[1] {
            points.append(#"{"label":"d","calls":\#(utc.component(.day, from: date))}"#)
            date = date.addingTimeInterval(86_400)
        }
        let body = #"{"bucket":"day","series":[\#(points.joined(separator: ","))]}"#
        return (Data(body.utf8), response)
    }
}

@Suite struct HeatmapTests {
    /// 2026-11-09 is a Monday. The start is this week's Monday 52 weeks back, whichever day of the
    /// week today is, and moves on only with the next Monday.
    @Test(arguments: [
        ("2026-11-09", "2025-11-10"), ("2026-11-10", "2025-11-10"),
        ("2026-11-15", "2025-11-10"), ("2026-11-16", "2025-11-17"),
    ])
    func startsOnTheMonday52WeeksBeforeThisWeeks(today: String, start: String) throws {
        #expect(try Heatmap.start(before: day(today), calendar: utc) == day(start))
    }

    /// Past 60 days the gateway answers in weeks, so every range has to stay under that while
    /// together they cover each day from the start through today exactly once.
    @Test(arguments: ["2026-11-09", "2026-11-10", "2026-11-15", "2028-02-29"])
    func rangesCoverEveryDayOnce(today: String) throws {
        let today = try day(today)
        let ranges = Heatmap.ranges(through: today, calendar: utc)
        #expect(ranges.allSatisfy { (2...Heatmap.maxRangeDays).contains($0.count) })
        #expect(ranges.first?.first == Heatmap.start(before: today, calendar: utc))
        #expect(ranges.last?.last == today)
        for (range, next) in zip(ranges, ranges.dropFirst()) {
            #expect(next.first == range.last.addingTimeInterval(86_400))
        }
    }

    @Test func rangesOfATuesdayAreSevenNearEqualOnes() throws {
        let ranges = Heatmap.ranges(through: try day("2026-11-10"), calendar: utc)
        #expect(ranges.map(\.count) == [53, 53, 52, 52, 52, 52, 52])
        #expect(ranges.first?.query == "2025-11-10..2026-01-01")
        #expect(ranges.last?.query == "2026-09-20..2026-11-10")
    }

    /// The dates sent are the calendar's own, not UTC's: east of Greenwich local midnight is still
    /// the day before in UTC, and a range across a clock change keeps one entry per date.
    @Test func rangeIsWrittenInTheCalendarsZone() throws {
        let shanghai = calendar(in: try #require(TimeZone(identifier: "Asia/Shanghai")))
        let october = try #require(
            shanghai.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        #expect(
            DayRange(first: october, count: 7, calendar: shanghai).query
                == "2026-10-01..2026-10-07")

        let newYork = calendar(in: try #require(TimeZone(identifier: "America/New_York")))
        let march = try #require(newYork.date(from: DateComponents(year: 2026, month: 3, day: 7)))
        let range = DayRange(first: march, count: 3, calendar: newYork)
        #expect(range.query == "2026-03-07..2026-03-09")
        #expect(range.days.map { newYork.component(.day, from: $0) } == [7, 8, 9])
        #expect(range.days.allSatisfy { newYork.startOfDay(for: $0) == $0 })
    }

    @Test func stitchesDayPointsOntoTheirDatesByPosition() throws {
        let ranges = [
            DayRange(first: try day("2026-01-30"), count: 2, calendar: utc),
            DayRange(first: try day("2026-02-01"), count: 3, calendar: utc),
        ]
        let series = [try dayPoints(calls: [1, 0]), try dayPoints(calls: [3, 4, 0])]
        let heatmap = try Heatmap(ranges: ranges, series: series, calendar: utc)
        #expect(heatmap.days.map(\.totals.calls) == [1, 0, 3, 4, 0])
        #expect(
            heatmap.days.map { $0.date.formatted(dayStyle) }
                == ["2026-01-30", "2026-01-31", "2026-02-01", "2026-02-02", "2026-02-03"])
        #expect(heatmap.totals.calls == 8)
        #expect(heatmap.activeDays == 3)
        #expect(heatmap.hasCalls)
    }

    /// A gateway that does not know picked ranges answers for its default 30 days; laying those
    /// 30 points over 53 days would put every one on a wrong date.
    @Test func refusesASeriesOfAnotherLength() throws {
        let ranges = [DayRange(first: try day("2025-11-10"), count: 53, calendar: utc)]
        let series = [try dayPoints(calls: Array(repeating: 1, count: 30))]
        do {
            _ = try Heatmap(ranges: ranges, series: series, calendar: utc)
            Issue.record("应当抛错")
        } catch {
            guard case .decoding = error else {
                Issue.record("应当是 decoding，实际是 \(error)")
                return
            }
        }
    }

    /// With few active days a day is graded by its share of the busiest: a quarter is level 1,
    /// just over half is level 3.
    @Test func fewDaysAreGradedByShareOfTheBusiest() {
        let scale = HeatScale(values: [0, 10, 25, 50, 51, 100, 0])
        #expect([0, 10, 25, 50, 51, 100].map(scale.level(of:)) == [0, 1, 1, 2, 3, 4])
        #expect(HeatScale(values: [0, 0]).level(of: 5) == 0)
    }

    /// From eight active days up a day is graded by quartile, so one outlier does not flatten the
    /// rest: next to a day of 1000, days of 1 to 7 still spread over levels 1 to 3.
    @Test func manyDaysAreGradedByQuartile() {
        let scale = HeatScale(values: [1, 2, 3, 4, 5, 6, 7, 1000, 0, 0])
        #expect(
            [0, 1, 2, 3, 4, 5, 6, 7, 1000].map(scale.level(of:)) == [0, 1, 1, 1, 2, 2, 3, 3, 4])
    }

    /// The start Monday is Nov 10, early enough in November to be named; Nov 2 a year later
    /// begins the week before the last and is named again.
    @Test func monthIsNamedAtTheWeekItsFirstMondayFallsIn() throws {
        let labels = try emptyYear(through: "2026-11-10").monthLabels()
        #expect(
            labels == [
                0: "Nov", 3: "Dec", 8: "Jan", 12: "Feb", 16: "Mar", 21: "Apr", 25: "May",
                29: "Jun", 34: "Jul", 38: "Aug", 43: "Sep", 47: "Oct", 51: "Nov",
            ])
    }

    /// Starting on Nov 24, November is mostly gone and stays unnamed. When this week's Monday is
    /// the first of its month (Nov 2), the last column has no room for the name.
    @Test func monthMostlyGoneOrJustBegunIsNotNamed() throws {
        let late = try emptyYear(through: "2026-11-23").monthLabels()
        #expect(late[0] == nil)
        #expect(late[1] == "Dec")
        #expect(late.count == 12)

        let justBegun = try emptyYear(through: "2026-11-02")
        #expect(justBegun.weekCount == 53)
        let labels = justBegun.monthLabels()
        #expect(labels[0] == "Nov")
        #expect(labels[52] == nil)
        #expect(labels.count == 12)
    }

    /// Names are drawn unclipped, so two must never sit closer than three columns, whatever day
    /// the heatmap ends on.
    @Test func monthNamesNeverCrowd() throws {
        let first = try day("2026-01-01")
        for offset in 0..<400 {
            let today = first.addingTimeInterval(Double(offset) * 86_400)
            let ranges = Heatmap.ranges(through: today, calendar: utc)
            let days = ranges.flatMap(\.days).map { Heatmap.Day(date: $0, totals: UsageTotals()) }
            let weeks = Heatmap(days: days, calendar: utc).monthLabels().keys.sorted()
            #expect(zip(weeks, weeks.dropFirst()).allSatisfy { $1 - $0 >= 3 }, "\(today)")
        }
    }

    /// The ranges are fetched at once and answered in any order; every day must still get its own
    /// point, and each request asks for a single row, since only the series is used.
    @Test func clientFetchesTheYearAsRangesAndPutsEachDayOnItsDate() async throws {
        let gateway = DayPointGateway()
        let base = try #require(URL(string: "https://magpie.example.com"))
        let client = MagpieClient(baseURL: base, key: "k", transport: gateway)
        let heatmap = try await client.heatmap(through: try day("2026-11-10"), calendar: utc)

        #expect(heatmap.days.count == 366)
        #expect(heatmap.days.first?.date == (try day("2025-11-10")))
        #expect(heatmap.days.last?.date == (try day("2026-11-10")))
        #expect(heatmap.days.allSatisfy { $0.totals.calls == utc.component(.day, from: $0.date) })

        let queries = await gateway.queries
        #expect(queries.count == 7)
        #expect(queries.allSatisfy { $0["limit"] == "1" && $0["offset"] == "0" })
        #expect(queries.contains { $0["period"] == "2025-11-10..2026-01-01" })
    }
}
