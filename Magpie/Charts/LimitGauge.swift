import SwiftUI

/// 一条额度用掉了多少的圆环：绿、橙、红随比例变，用完了整圈红。
struct LimitGauge: View {
    let limit: LimitStatus

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0.001), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
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

    /// 费用额度优先；只限 tokens 的按 tokens 算。
    private var fraction: Double {
        if limit.spent {
            return 1
        }
        if let cap = limit.costLimit, cap > 0 {
            return limit.cost / cap
        }
        if let cap = limit.tokenLimit, cap > 0 {
            return Double(limit.tokens) / Double(cap)
        }
        return 0
    }

    private var usedText: String {
        if let cap = limit.costLimit, cap > 0 {
            return "\(Format.usd(limit.cost)) / \(Format.usd(cap))"
        }
        if let cap = limit.tokenLimit, cap > 0 {
            return "\(Format.tokens(limit.tokens)) / \(Format.tokens(cap))"
        }
        return "\(Format.count(limit.calls)) 次"
    }

    private var color: Color {
        switch fraction {
        case ..<0.6: .green
        case ..<0.85: .orange
        default: .red
        }
    }
}
