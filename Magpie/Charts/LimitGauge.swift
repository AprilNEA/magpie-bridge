import SwiftUI

/// Ring showing how much of one limit is used: green, orange, red follow the fraction, and the
/// whole ring is red once spent.
struct LimitGauge: View {
    let limit: LimitStatus

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                // The arc runs light to dark; the dark end is how far usage has got. The gradient
                // angle starts at 0 like trim does, then both rotate to the top together.
                Circle()
                    .trim(from: 0, to: arc)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.4), color], center: .center,
                            startAngle: .zero, endAngle: .degrees(360 * arc)),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: fraction)
                VStack(spacing: 0) {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 72, height: 72)
            .padding(5)
            VStack(spacing: 2) {
                Text(limit.title)
                    .font(.footnote.weight(.medium))
                Text(usedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if limit.spent {
                    Text("已用完")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.red)
                } else if let reset = limit.resetsAt {
                    Text("\(Format.when(reset)) 重置")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var fraction: Double { limit.usedFraction }
    private var usedText: String { limit.usedText }
    private var color: Color { limit.usageColor }

    /// The drawn arc: 0 still draws a sliver, and anything above 1 is capped.
    private var arc: Double {
        min(max(fraction, 0.001), 1)
    }
}

extension LimitStatus {
    /// Green, orange, red follow the used fraction; the gauge and the progress bar share this.
    var usageColor: Color {
        switch usedFraction {
        case ..<0.6: .green
        case ..<0.85: .orange
        default: .red
        }
    }
}
