import Foundation

/// 页面上数字和时间的写法，和网页 /me 保持一致。
nonisolated enum Format {
    /// 1.2万、35K 这样的紧凑写法。
    static func tokens(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func count(_ count: Int) -> String {
        count.formatted()
    }

    /// 100 美元以上不显示分。
    static func usd(_ amount: Double) -> String {
        amount >= 100 ? "$" + Int(amount.rounded()).formatted() : String(format: "$%.2f", amount)
    }

    /// 平均每次调用这种很小的金额：1 美元以上和 usd 一样，1 美分以上三位小数，再小四位。
    static func unitCost(_ amount: Double) -> String {
        switch amount {
        case 1...: usd(amount)
        case 0.01...: String(format: "$%.3f", amount)
        default: String(format: "$%.4f", amount)
        }
    }

    static func when(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func duration(ms: Int64) -> String {
        ms < 1000 ? "\(ms) ms" : String(format: "%.1f s", Double(ms) / 1000)
    }

    /// 394 B、1.2 KB 这样的字节数。
    static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }
}
