import Charts
import SwiftUI

/// One period's tokens as a single horizontal bar split into four segments: input, output, cache
/// read, cache write. Below it, one row per kind: amount and share right-aligned, styled like the
/// breakdown chart's legend, so neither names nor numbers get squeezed into ellipses.
struct TokenMixChart: View {
    let totals: UsageTotals

    var body: some View {
        let names = TokenKind.allCases.map(\.title)
        VStack(alignment: .leading, spacing: 10) {
            Chart(TokenKind.allCases) { kind in
                BarMark(x: .value("Tokens", kind.value(of: totals)))
                    .foregroundStyle(by: .value("类型", kind.title))
            }
            .chartForegroundStyleScale(domain: names, range: ChartData.styles(for: names))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartPlotStyle { plot in plot.clipShape(Capsule()) }
            .frame(height: 14)
            .animation(.snappy, value: totals)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                ForEach(TokenKind.allCases) { kind in
                    legend(kind, color: ChartData.color(of: kind.title, in: names))
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overview.usage.mix")
    }

    private func legend(_ kind: TokenKind, color: Color) -> some View {
        let value = kind.value(of: totals)
        let fraction = totals.tokens > 0 ? Double(value) / Double(totals.tokens) : 0
        return GridRow {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(kind.title)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.tokens(value))
                .fontWeight(.medium)
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }
}
