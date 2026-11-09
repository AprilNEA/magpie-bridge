import SwiftUI

/// 一条额度的明细行：名字和已用 / 上限、进度条、剩余多少、调用次数和重置时间。
/// 概览页的圆环只给比例，设置页用这个把数字写全。
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
