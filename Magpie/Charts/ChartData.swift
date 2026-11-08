import SwiftUI

/// 把一页账本整理成图表吃的形状：按某个维度、某个指标，前几名各占一份，其余并成「其他」。
/// 颜色跟着名字走，趋势图和环形图里同一个模型是同一种颜色。
nonisolated enum ChartData {
    static let otherName = "其他"
    /// 图例最多几项；再多手机上就看不清了。
    static let keep = 5

    /// 堆叠柱的一段：某个桶里某个成员的量。
    struct Stack: Hashable, Identifiable, Sendable {
        var label: String
        var name: String
        var value: Double

        var id: String { label + "/" + name }
    }

    /// 环形图的一块。
    struct Slice: Hashable, Identifiable, Sendable {
        var name: String
        var value: Double
        /// 占整个时段的比例，0 到 1。
        var fraction: Double

        var id: String { name }
    }

    /// 整个时段里按 metric 最大的前 keep 个成员，大的在前。
    static func leaders(
        in ledger: RequestLedger, by dimension: Dimension, metric: UsageMetric, keep: Int = keep
    ) -> [UsageShare] {
        let shares = ledger.shares(by: dimension).filter { metric.value(of: $0.totals) > 0 }
        let sorted = shares.sorted { metric.value(of: $0.totals) > metric.value(of: $1.totals) }
        return Array(sorted.prefix(keep))
    }

    /// 图例上的名字：领先的成员，加上有剩余时的「其他」。顺序就是颜色的顺序。
    static func names(
        in ledger: RequestLedger, by dimension: Dimension, metric: UsageMetric, keep: Int = keep
    ) -> [String] {
        let leaders = leaders(in: ledger, by: dimension, metric: metric, keep: keep)
        var names = leaders.map(\.name)
        let rest =
            metric.value(of: ledger.totals) - leaders.reduce(0) { $0 + metric.value(of: $1.totals) }
        if rest > 0.000_001 {
            names.append(otherName)
        }
        return names
    }

    /// 每个桶、每个领先成员一段；桶里剩下的量算到「其他」。量为 0 的不出段。
    static func stacks(
        in ledger: RequestLedger, by dimension: Dimension, metric: UsageMetric, keep: Int = keep
    ) -> [Stack] {
        let leaders = leaders(in: ledger, by: dimension, metric: metric, keep: keep)
        var out: [Stack] = []
        for point in ledger.series {
            let parts = point.parts(by: dimension)
            var counted = 0.0
            for leader in leaders {
                let value = parts[leader.id].map(metric.value(of:)) ?? 0
                counted += value
                if value > 0 {
                    out.append(Stack(label: point.label, name: leader.name, value: value))
                }
            }
            let rest = metric.value(of: point.totals) - counted
            if rest > 0.000_001 {
                out.append(Stack(label: point.label, name: otherName, value: rest))
            }
        }
        return out
    }

    /// 环形图的份额：领先成员加「其他」，按整个时段的合计算占比。
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
        if rest > 0.000_001 {
            slices.append(Slice(name: otherName, value: rest, fraction: rest / total))
        }
        return slices
    }

    /// 横轴上标出来的刻度：一屏最多 limit 个，均匀挑，最后一个（最近的桶）一定标出来。
    /// 图能横向滚动时传 window（一屏几个桶），刻度按一屏的密度挑，而不是按整段。
    static func axisLabels(_ labels: [String], window: Int? = nil, limit: Int = 7) -> [String] {
        let perScreen = min(window ?? labels.count, labels.count)
        let stride = max(1, Int((Double(perScreen) / Double(limit)).rounded(.up)))
        let last = labels.count - 1
        return labels.enumerated().filter { (last - $0.offset) % stride == 0 }.map(\.element)
    }

    static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .mint]

    /// 画图用的填充：和 colors 一样的顺序，每种颜色带一点由亮到暗的渐变。
    static func styles(for names: [String]) -> [AnyGradient] {
        colors(for: names).map(\.gradient)
    }

    /// 和 names 一一对应的颜色；「其他」永远是灰的。
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
