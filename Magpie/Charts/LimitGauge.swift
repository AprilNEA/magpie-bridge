import SwiftUI

/// 一条额度用掉了多少的圆环：绿、橙、红随比例变，用完了整圈红。
struct LimitGauge: View {
    let limit: LimitStatus

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                // 弧从淡到深，深的一头是用到哪儿了。渐变的角度和 trim 一样从 0 起算，再一起转到顶上。
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

    /// 画出来的那段弧：0 也画一点点，超过 1 封顶。
    private var arc: Double {
        min(max(fraction, 0.001), 1)
    }
}

extension LimitStatus {
    /// 绿、橙、红随用掉的比例变；圆环和进度条用同一套。
    var usageColor: Color {
        switch usedFraction {
        case ..<0.6: .green
        case ..<0.85: .orange
        default: .red
        }
    }
}
