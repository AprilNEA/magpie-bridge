import SwiftUI

/// Detail row for one limit: name and used / cap, a progress bar, how much is left, call count, and
/// reset time.
/// The gauge on the overview tab only gives the fraction; the settings tab uses this row to spell
/// out the numbers.
struct LimitRow: View {
    let limit: LimitStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.title)
                Spacer()
                Text(limit.usedText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: min(limit.usedFraction, 1))
                .tint(limit.usageColor)
            HStack(spacing: 4) {
                if limit.spent {
                    Text("已用完")
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                } else if let left = limit.leftText {
                    Text(left)
                }
                Spacer()
                Text("\(Format.count(limit.calls)) 次调用")
                if let reset = limit.resetsAt {
                    Text("· \(Format.when(reset)) 重置")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
