import Charts
import SwiftUI

/// 一个时段里各家占多少的环形图，中间是合计；点一块，中间换成它的名字和占比，点中间取消。
struct ShareChart: View {
    let slices: [ChartData.Slice]
    let names: [String]
    let dimension: Dimension
    let metric: UsageMetric

    @State private var selectedName: String?

    private let innerRatio = 0.64

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value(metric.title, slice.value),
                innerRadius: .ratio(innerRatio),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(by: .value(dimension.title, slice.name))
            .opacity(selected == nil || selected?.name == slice.name ? 1 : 0.35)
        }
        .chartForegroundStyleScale(domain: names, range: ChartData.styles(for: names))
        .chartLegend(.hidden)
        // 和趋势图一样不用系统的按住选择，点一下选、再点或点中间取消。
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let anchor = proxy.plotFrame else { return }
                        let frame = geometry[anchor]
                        let point = CGPoint(x: location.x - frame.minX, y: location.y - frame.minY)
                        let hit = slice(at: point, in: proxy, plotSize: frame.size)?.name
                        withAnimation(.snappy) {
                            selectedName = hit == selectedName ? nil : hit
                        }
                    }
            }
        }
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    center
                        .frame(width: frame.width * 0.56)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(height: 200)
        .animation(.snappy, value: slices)
    }

    private var center: some View {
        VStack(spacing: 2) {
            if let selected {
                Text(selected.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(selected.fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityIdentifier("overview.share.selected")
                Text(metric.format(selected.value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(metric.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(metric.format(slices.reduce(0) { $0 + $1.value }))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(slices.count) 项")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 换了维度以后旧的名字可能不在了，那就当没选。
    private var selected: ChartData.Slice? {
        guard let selectedName else { return nil }
        return slices.first { $0.name == selectedName }
    }

    /// 手指落在环上的那一块：按角度对应的累计值找。落在中间的空心里不算任何一块。
    private func slice(at point: CGPoint, in proxy: ChartProxy, plotSize: CGSize) -> ChartData
        .Slice?
    {
        let radius = min(plotSize.width, plotSize.height) / 2
        let distance = hypot(point.x - plotSize.width / 2, point.y - plotSize.height / 2)
        guard distance >= radius * innerRatio else { return nil }
        guard let value = proxy.value(atAngle: proxy.angle(at: point), as: Double.self) else {
            return nil
        }
        var running = 0.0
        for slice in slices {
            running += slice.value
            if value <= running {
                return slice
            }
        }
        return slices.last
    }
}

/// 环形图下面的一行：颜色、名字、量和占比，再加一条占比的细条。
struct ShareRow: View {
    let slice: ChartData.Slice
    let color: Color
    let metric: UsageMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(slice.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(metric.format(slice.value))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(slice.fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            ProgressView(value: slice.fraction)
                .tint(color)
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
        }
        .padding(.vertical, 2)
    }
}
