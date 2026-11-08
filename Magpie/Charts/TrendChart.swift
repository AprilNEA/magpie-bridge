import Charts
import SwiftUI

/// 一个时段的用量按桶堆起来的柱状图：点一根柱子，看那个桶里各家的量；再点一下取消。
/// 桶多到一屏放不下（30 天、全部）就能横向滚动，一开始停在最近的桶。
struct TrendChart: View {
    let ledger: RequestLedger
    let dimension: Dimension
    let metric: UsageMetric

    @State private var selectedLabel: String?

    /// 能滚动时一屏放几个桶。小时桶（今天）24 根放得下，不滚。
    /// 分类轴一屏实际只露出 window - 1 根、最左边那根贴着边；刻度是从最后一根往前每 3 根标一个，
    /// 取 15 时贴边那根正好轮不到标，不然它的标签会被切掉一半。
    static let window = 15

    var body: some View {
        let leaders = ChartData.leaders(in: ledger, by: dimension, metric: metric)
        let names = ChartData.names(in: ledger, by: dimension, metric: metric)
        let stacks = ChartData.stacks(in: ledger, by: dimension, metric: metric)
        let labels = ledger.series.map(\.label)
        let scrolls = ledger.bucket != .hour && labels.count > Self.window
        let shownLabels = Set(
            ChartData.axisLabels(
                labels, window: scrolls ? Self.window : nil, limit: scrolls ? 5 : 7))
        // 换了时段以后旧的选择可能对不上任何桶，那就当没选。
        let selectedPoint = selectedPoint
        VStack(alignment: .leading, spacing: 8) {
            if stacks.isEmpty {
                Text("这段时间没有\(metric.title.lowercased())。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart {
                    ForEach(stacks) { stack in
                        BarMark(
                            x: .value("时间", stack.label),
                            y: .value(metric.title, stack.value)
                        )
                        .cornerRadius(2)
                        .foregroundStyle(by: .value(dimension.title, stack.name))
                        .opacity(
                            selectedPoint == nil || selectedPoint?.label == stack.label ? 1 : 0.35)
                    }
                    if let point = selectedPoint {
                        RuleMark(x: .value("时间", point.label))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartForegroundStyleScale(domain: names, range: ChartData.styles(for: names))
                .chartXScale(domain: labels)
                .modifier(ScrollsToNewest(labels: labels, window: scrolls ? Self.window : nil))
                // 分类轴上 AxisMarks(values:) 不会少画刻度，只能每个桶都来一遍、挑着写字。
                // 能滚动时最后一个标签居中会有一半被视口切掉，改成右对齐到刻度上。
                .chartXAxis {
                    AxisMarks { value in
                        if let label = value.as(String.self), shownLabels.contains(label) {
                            AxisValueLabel(
                                anchor: scrolls && label == labels.last ? .topTrailing : nil
                            ) {
                                Text(label)
                            }
                        }
                    }
                }
                // 系统自带的选择手势要按住才出、松手就没，在滚动页里不好用；换成点一下选、再点取消。
                // 明细卡片不用 annotation：它会浮到图外面被列表裁掉。放在图内、选中那根柱子对面的上角。
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        let bounds = CGRect(origin: .zero, size: geometry.size)
                        let plot = proxy.plotFrame.map { geometry[$0] } ?? bounds
                        // 图能滚动时绘图区比图宽、左边一截在屏幕外；卡片只能放在看得见的那段里。
                        let visible = plot.intersection(bounds)
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard
                                    let label = proxy.value(
                                        atX: location.x - plot.minX, as: String.self)
                                else { return }
                                withAnimation(.snappy) {
                                    selectedLabel = selectedLabel == label ? nil : label
                                }
                            }
                        if let point = selectedPoint, let x = proxy.position(forX: point.label) {
                            SelectionCard(
                                point: point, dimension: dimension, metric: metric,
                                leaders: leaders, names: names
                            )
                            .onTapGesture {
                                withAnimation(.snappy) { selectedLabel = nil }
                            }
                            .padding(4)
                            .frame(
                                width: visible.width, height: visible.height,
                                alignment: plot.minX + x < visible.midX ? .topTrailing : .topLeading
                            )
                            .offset(x: visible.minX, y: visible.minY)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(metric.format(number))
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
                .frame(height: 220)
            }
        }
        .animation(.snappy, value: metric)
        .animation(.snappy, value: dimension)
    }

    private var selectedPoint: SeriesPoint? {
        guard let selectedLabel else { return nil }
        return ledger.series.first { $0.label == selectedLabel }
    }
}

/// 桶多到一屏放不下就横向滚动，一开始停在最近的一屏。
/// 初始位置只在图第一次出现时生效，所以桶一变（换了时段）就按 labels 重建一张图。
private struct ScrollsToNewest: ViewModifier {
    let labels: [String]
    /// 一屏放几个桶；nil 就不滚。
    let window: Int?

    func body(content: Content) -> some View {
        if let window, labels.count > window {
            // 初始位置是「哪个桶贴着左边」。让最后一个桶贴左边，滚动会卡在最右端，一屏正好是最近的那些桶；
            // 要是按 count - window 算，分类轴一屏实际放不满 window 个，最后一根会被切掉。
            content
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: window)
                .chartScrollPosition(initialX: labels[labels.count - 1])
                .id(labels)
        } else {
            content
        }
    }
}

/// 选中一根柱子时浮在上面的小卡片：这个桶的合计和前几名。
private struct SelectionCard: View {
    let point: SeriesPoint
    let dimension: Dimension
    let metric: UsageMetric
    /// 整个时段领先的成员，桶里按它们的 id 找量，按它们的名字显示。
    let leaders: [UsageShare]
    let names: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(point.label).font(.caption.weight(.semibold))
                Spacer(minLength: 12)
                Text(metric.format(metric.value(of: point.totals)))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            ForEach(parts, id: \.name) { part in
                HStack(spacing: 4) {
                    Circle()
                        .fill(ChartData.color(of: part.name, in: names))
                        .frame(width: 6, height: 6)
                    Text(part.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(metric.format(part.value)).monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if point.totals.errors > 0 {
                Text("\(point.totals.errors) 次失败")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(minWidth: 140, maxWidth: 220, alignment: .leading)
        // 按内容定宽，别被外面给的整块绘图区撑满。
        .fixedSize(horizontal: true, vertical: false)
        .background(
            Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.separator), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.selection")
    }

    private var parts: [(name: String, value: Double)] {
        let byID = point.parts(by: dimension)
        var out: [(name: String, value: Double)] = []
        var counted = 0.0
        for leader in leaders {
            let value = byID[leader.id].map(metric.value(of:)) ?? 0
            counted += value
            if value > 0 {
                out.append((leader.name, value))
            }
        }
        let rest = metric.value(of: point.totals) - counted
        if rest > 0.000_001 {
            out.append((ChartData.otherName, rest))
        }
        return out
    }
}
