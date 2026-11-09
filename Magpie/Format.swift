import Foundation

/// How numbers and times are written on screen, consistent with the /me web page.
nonisolated enum Format {
    /// Compact notation such as 35K, or "1.2 wan" (12 thousand) in a Chinese locale.
    static func tokens(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func count(_ count: Int) -> String {
        count.formatted()
    }

    /// From 100 dollars up, cents are not shown.
    static func usd(_ amount: Double) -> String {
        amount >= 100 ? "$" + Int(amount.rounded()).formatted() : String(format: "$%.2f", amount)
    }

    /// Very small amounts such as the average per call: from 1 dollar up same as usd, from 1 cent
    /// up three decimals, anything smaller four.
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

    /// Byte counts such as 394 B or 1.2 KB.
    static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }
}
