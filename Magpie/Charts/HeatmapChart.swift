import SwiftUI

/// A year of days as a calendar grid, as the web dashboard's heatmap draws it: a week per column
/// with Monday on top, each day shaded by how busy it was among the days that had anything.
/// The grid scrolls horizontally and starts at the newest week. The line below tells the year's
/// figures; tap a day and it tells that day's instead, tap the day again to cancel.
/// The grid is a Canvas, not a Swift Charts plot: a day's square has a fixed size, where a plot
/// would scale it to the data and to the width.
struct HeatmapChart: View {
    let heatmap: Heatmap
    let metric: UsageMetric

    @State private var selected: Date?
    /// Height of the month names above the grid.
    @ScaledMetric(relativeTo: .caption2) private var monthHeight: CGFloat = 16

    /// Side of one day's square.
    private static let cell: CGFloat = 15
    /// Space between two squares.
    private static let gap: CGFloat = 3
    private static let pitch = cell + gap
    /// How much of the accent color levels 1 to 4 get, as the web dashboard shades them.
    private static let shades = [0.22, 0.45, 0.7, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 6) {
                weekdays
                ScrollView(.horizontal) {
                    grid
                }
                .defaultScrollAnchor(.trailing)
                .scrollIndicators(.hidden)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("过去一年每天的\(metric.title)")
                .accessibilityValue("\(heatmap.activeDays) 天有调用")
                .accessibilityIdentifier("overview.heatmap")
            }
            HStack(alignment: .bottom) {
                detail
                Spacer(minLength: 8)
                legend
            }
        }
        .padding(.vertical, 4)
    }

    /// Names beside the rows of Monday, Wednesday, Friday, and Sunday; the rows between go unnamed,
    /// as on the web dashboard.
    private var weekdays: some View {
        let symbols = heatmap.calendar.veryShortStandaloneWeekdaySymbols
        return VStack(spacing: Self.gap) {
            ForEach(0..<7, id: \.self) { row in
                // Row 0 is Monday; the calendar's symbols start on Sunday.
                Text(row.isMultiple(of: 2) ? symbols[(row + 1) % 7] : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(height: Self.cell)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        let scale = HeatScale(values: heatmap.days.map { metric.value(of: $0.totals) })
        let labels = heatmap.monthLabels()
        return Canvas { context, _ in
            for (week, label) in labels {
                context.draw(
                    Text(label).font(.caption2).foregroundStyle(Color.secondary),
                    at: CGPoint(x: CGFloat(week) * Self.pitch, y: 0), anchor: .topLeading)
            }
            for (index, day) in heatmap.days.enumerated() {
                let square = Path(roundedRect: frame(of: index), cornerRadius: 3.5)
                let level = scale.level(of: metric.value(of: day.totals))
                context.fill(square, with: .color(Self.fill(level: level)))
                if day.date == selected {
                    context.stroke(square, with: .color(.primary), lineWidth: 1.5)
                }
            }
        }
        .frame(
            width: CGFloat(heatmap.weekCount) * Self.pitch - Self.gap,
            height: monthHeight + 7 * Self.pitch - Self.gap
        )
        .contentShape(Rectangle())
        .onTapGesture { location in
            guard let index = index(at: location) else { return }
            let date = heatmap.days[index].date
            withAnimation(.snappy) {
                selected = selected == date ? nil : date
            }
        }
    }

    /// The selected day and its figures, or the whole year's while no day is selected.
    private var detail: some View {
        let day = heatmap.days.first { $0.date == selected }
        return VStack(alignment: .leading, spacing: 2) {
            Text(
                day?.date.formatted(heatmap.dateStyle.year().month().day().weekday(.abbreviated))
                    ?? "\(heatmap.activeDays) 天有调用"
            )
            .font(.caption.weight(.semibold))
            Text(figures(of: day?.totals ?? heatmap.totals))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(day == nil ? "overview.heatmap.year" : "overview.heatmap.selected")
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Text("少")
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Self.fill(level: level))
                    .frame(width: 10, height: 10)
            }
            Text("多")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private static func fill(level: Int) -> Color {
        level == 0 ? Color(.systemFill) : Color.accentColor.opacity(shades[level - 1])
    }

    /// Where the day at index is drawn: a column per week, Monday on top, below the month names.
    private func frame(of index: Int) -> CGRect {
        CGRect(
            x: CGFloat(index / 7) * Self.pitch, y: monthHeight + CGFloat(index % 7) * Self.pitch,
            width: Self.cell, height: Self.cell)
    }

    /// The day under a point of the grid; the space after a square counts as that square.
    private func index(at point: CGPoint) -> Int? {
        let row = Int(((point.y - monthHeight) / Self.pitch).rounded(.down))
        guard point.x >= 0, (0..<7).contains(row) else { return nil }
        let index = Int(point.x / Self.pitch) * 7 + row
        return heatmap.days.indices.contains(index) ? index : nil
    }

    /// Tokens, requests, and cost of some calls, the metric the grid shades coming first.
    private func figures(of totals: UsageTotals) -> String {
        guard totals.calls > 0 else { return "没有请求" }
        var parts: [(metric: UsageMetric, text: String)] = [
            (.tokens, "\(Format.tokens(totals.tokens)) tokens"),
            (.calls, "\(Format.count(totals.calls)) 次请求"),
        ]
        if totals.cost > 0 {
            parts.append((.cost, "约 \(Format.usd(totals.cost))"))
        }
        let ordered = parts.filter { $0.metric == metric } + parts.filter { $0.metric != metric }
        return ordered.map(\.text).joined(separator: " · ")
    }
}
