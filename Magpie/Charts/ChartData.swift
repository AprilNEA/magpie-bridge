import SwiftUI

/// Shapes one ledger page into what the charts consume: by one dimension and one metric, the top
/// few members each get a share and the rest merge into "Other".
/// Colors follow names, so the same model gets the same color in the trend chart and the donut
/// chart.
nonisolated enum ChartData {
    static let otherName = "其他"
    /// Maximum number of legend entries; any more becomes unreadable on a phone.
    static let keep = 5

    /// One segment of a stacked bar: one member's amount in one bucket.
    struct Stack: Hashable, Identifiable, Sendable {
        var label: String
        var name: String
        var value: Double

        var id: String { label + "/" + name }
    }

    /// One slice of the donut chart.
    struct Slice: Hashable, Identifiable, Sendable {
        var name: String
        var value: Double
        /// Fraction of the whole period, 0 to 1.
        var fraction: Double

        var id: String { name }
    }

    /// The top keep members by metric over the whole period, largest first.
    static func leaders(
        in ledger: RequestLedger, by dimension: Dimension, metric: UsageMetric, keep: Int = keep
    ) -> [UsageShare] {
        let shares = ledger.shares(by: dimension).filter { metric.value(of: $0.totals) > 0 }
        let sorted = shares.sorted { metric.value(of: $0.totals) > metric.value(of: $1.totals) }
        return Array(sorted.prefix(keep))
    }

    /// Names on the legend: the leading members, plus "Other" when there is a remainder. The order
    /// is the color order.
    static func names(
        in ledger: RequestLedger, by dimension: Dimension, metric: UsageMetric, keep: Int = keep
    ) -> [String] {
        let leaders = leaders(in: ledger, by: dimension, metric: metric, keep: keep)
        var names = leaders.map(\.name)
        let rest =
            metric.value(of: ledger.totals) - leaders.reduce(0) { $0 + metric.value(of: $1.totals) }
        if rest >= metric.resolution {
            names.append(otherName)
        }
        return names
    }

    /// One segment per bucket per legend name; the bucket's leftover amount counts toward "Other".
    /// A segment is emitted even when the amount is 0: a bar that cannot be drawn does no harm, but
    /// in the area chart every line needs a point in every bucket, or the stacking misaligns.
    static func stacks(
        in ledger: RequestLedger, by dimension: Dimension, metric: UsageMetric, keep: Int = keep
    ) -> [Stack] {
        let leaders = leaders(in: ledger, by: dimension, metric: metric, keep: keep)
        let hasOther =
            names(in: ledger, by: dimension, metric: metric, keep: keep).last == otherName
        var out: [Stack] = []
        for point in ledger.series {
            let parts = point.parts(by: dimension)
            var counted = 0.0
            for leader in leaders {
                let value = parts[leader.id].map(metric.value(of:)) ?? 0
                counted += value
                out.append(Stack(label: point.label, name: leader.name, value: value))
            }
            if hasOther {
                let rest = max(0, metric.value(of: point.totals) - counted)
                out.append(Stack(label: point.label, name: otherName, value: rest))
            }
        }
        return out
    }

    /// Height of each segment in one bucket once stacked; the area chart puts dots at these
    /// positions when the bucket is selected. A segment with amount 0 has no top of its own.
    static func tops(of stacks: [Stack], at label: String) -> [(name: String, value: Double)] {
        var height = 0.0
        return stacks.filter { $0.label == label && $0.value > 0 }.map { stack in
            height += stack.value
            return (stack.name, height)
        }
    }

    /// Shares for the donut chart: the leading members plus "Other", with fractions taken against
    /// the whole period's total.
    static func slices(
        in ledger: RequestLedger, by dimension: Dimension, metric: UsageMetric, keep: Int = keep
    ) -> [Slice] {
        let total = metric.value(of: ledger.totals)
        guard total > 0 else { return [] }
        let leaders = leaders(in: ledger, by: dimension, metric: metric, keep: keep)
        var slices = leaders.map { share in
            let value = metric.value(of: share.totals)
            return Slice(name: share.name, value: value, fraction: value / total)
        }
        let rest = total - slices.reduce(0) { $0 + $1.value }
        if rest >= metric.resolution {
            slices.append(Slice(name: otherName, value: rest, fraction: rest / total))
        }
        return slices
    }

    /// Ticks labeled on the horizontal axis: at most limit per screen, picked evenly, and the last
    /// one (the most recent bucket) is always labeled.
    /// When the chart scrolls horizontally, pass window (buckets per screen) so ticks are picked at
    /// the density of one screen rather than of the whole range.
    static func axisLabels(_ labels: [String], window: Int? = nil, limit: Int = 7) -> [String] {
        let perScreen = min(window ?? labels.count, labels.count)
        let stride = max(1, Int((Double(perScreen) / Double(limit)).rounded(.up)))
        let last = labels.count - 1
        return labels.enumerated().filter { (last - $0.offset) % stride == 0 }.map(\.element)
    }

    static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .mint]

    /// Fills for drawing: same order as colors, each color with a slight light-to-dark gradient.
    static func styles(for names: [String]) -> [AnyGradient] {
        colors(for: names).map(\.gradient)
    }

    /// Colors matching names one to one; "Other" is always gray.
    static func colors(for names: [String]) -> [Color] {
        var index = 0
        return names.map { name in
            if name == otherName {
                return Color.gray.opacity(0.6)
            }
            defer { index += 1 }
            return palette[index % palette.count]
        }
    }

    static func color(of name: String, in names: [String]) -> Color {
        guard let index = names.firstIndex(of: name) else { return .gray }
        return colors(for: names)[index]
    }
}
