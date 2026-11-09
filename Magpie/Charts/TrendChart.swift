import Charts
import SwiftUI

/// One period's usage stacked by bucket, drawn as bars or as a smooth area: tap a bucket to see
/// each member's amount in that bucket; tap again to cancel.
/// When the buckets do not fit on one screen (30 days, all), the chart scrolls horizontally and
/// starts at the most recent bucket.
struct TrendChart: View {
    /// Whether the same stacked data is drawn as bars or as an area.
    enum Style: String, CaseIterable, Identifiable {
        case bars, area

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bars: "柱状图"
            case .area: "面积图"
            }
        }

        var symbol: String {
            switch self {
            case .bars: "chart.bar.xaxis"
            case .area: "chart.xyaxis.line"
            }
        }
    }

    let ledger: RequestLedger
    let dimension: Dimension
    let metric: UsageMetric
    let style: Style

    @State private var selectedLabel: String?

    /// Buckets per screen when the chart scrolls. Hour buckets (today) fit all 24 bars and do not
    /// scroll.
    /// A category axis actually reveals only window - 1 bars per screen, with the leftmost bar
    /// flush against the edge; ticks are labeled every 3 bars counting back from the last one, and
    /// with 15 the flush bar is exactly the one skipped, otherwise its label would be half cut off.
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
        // After a period change the old selection may match no bucket; treat that as no selection.
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
                        if style == .area {
                            AreaMark(
                                x: .value("时间", stack.label),
                                y: .value(metric.title, stack.value)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(by: .value(dimension.title, stack.name))
                        } else {
                            BarMark(
                                x: .value("时间", stack.label),
                                y: .value(metric.title, stack.value)
                            )
                            .cornerRadius(2)
                            .foregroundStyle(by: .value(dimension.title, stack.name))
                            .opacity(
                                selectedPoint == nil || selectedPoint?.label == stack.label
                                    ? 1 : 0.35)
                        }
                    }
                    if let point = selectedPoint {
                        RuleMark(x: .value("时间", point.label))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        // The area chart cannot dim the other buckets, so instead each layer in the
                        // selected bucket gets a dot at its top.
                        if style == .area {
                            ForEach(ChartData.tops(of: stacks, at: point.label), id: \.name) {
                                top in
                                PointMark(
                                    x: .value("时间", point.label),
                                    y: .value(metric.title, top.value)
                                )
                                .symbol {
                                    Circle()
                                        .fill(ChartData.color(of: top.name, in: names))
                                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                        .frame(width: 9, height: 9)
                                }
                            }
                        }
                    }
                }
                .chartForegroundStyleScale(domain: names, range: ChartData.styles(for: names))
                .chartXScale(domain: labels)
                .modifier(ScrollsToNewest(labels: labels, window: scrolls ? Self.window : nil))
                // On a category axis AxisMarks(values:) does not draw fewer ticks, so the only way
                // is to visit every bucket and write labels selectively.
                // When scrolling, a centered last label would be half clipped by the viewport, so
                // it is right-aligned to the tick instead.
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
                // The system selection gesture only shows while pressing and vanishes on release,
                // which works poorly in a scrolling page; replaced with tap to select, tap again
                // to cancel.
                // The detail card does not use annotation: it would float outside the chart and be
                // clipped by the list. It sits inside the chart, in the top corner opposite the
                // selected bar.
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        let bounds = CGRect(origin: .zero, size: geometry.size)
                        let plot = proxy.plotFrame.map { geometry[$0] } ?? bounds
                        // When the chart scrolls, the plot area is wider than the chart and a
                        // stretch on the left is off screen; the card can only go in the visible
                        // part.
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

/// Scrolls horizontally when the buckets do not fit on one screen, starting at the most recent
/// screen.
/// The initial position only takes effect when the chart first appears, so whenever the buckets
/// change (period change) the chart is rebuilt keyed by labels.
private struct ScrollsToNewest: ViewModifier {
    let labels: [String]
    /// Buckets per screen; nil means no scrolling.
    let window: Int?

    func body(content: Content) -> some View {
        if let window, labels.count > window {
            // The initial position is "which bucket sits flush left". Putting the last bucket flush
            // left pins the scroll at the far right, so one screen is exactly the most recent
            // buckets; computing count - window instead would clip the last bar, because a category
            // axis does not actually fit window bars on one screen.
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

/// Small card floating over the chart when a bar is selected: this bucket's total and its top few
/// members.
private struct SelectionCard: View {
    let point: SeriesPoint
    let dimension: Dimension
    let metric: UsageMetric
    /// The leading members over the whole period; the bucket's amounts are looked up by their id
    /// and shown under their name.
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
        // Size the width to the content instead of filling the whole plot area given from outside.
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
