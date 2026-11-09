import Foundation

/// One limit on a key and the usage in its current window (budget.Status).
nonisolated struct LimitStatus: Decodable, Hashable, Identifiable, Sendable {
    /// day, week, month, or days / hours together with the count in days / hours.
    var period: String
    var days: Int?
    var hours: Int?
    var start: Date
    /// When the window resets; Go's zero time (year 1 AD) means there is none.
    var reset: Date
    var calls: Int
    var tokens: Int
    var cost: Double
    var tokenLimit: Int?
    var costLimit: Double?
    var tokensLeft: Int
    var costLeft: Double
    /// Used up; every request is rejected until the reset.
    var spent: Bool

    var id: String { "\(period)/\(days ?? 0)/\(hours ?? 0)" }

    var title: String {
        switch period {
        case "day": "每天"
        case "week": "每周"
        case "month": "每月"
        case "days": "每 \(days ?? 0) 天"
        case "hours": "每 \(hours ?? 0) 小时"
        default: period
        }
    }

    var resetsAt: Date? {
        reset > Date(timeIntervalSince1970: 0) ? reset : nil
    }

    /// The fraction used: the cost limit comes first, a tokens-only limit goes by tokens; spent
    /// counts as 1, no limit counts as 0.
    var usedFraction: Double {
        if spent {
            return 1
        }
        if let cap = costLimit, cap > 0 {
            return cost / cap
        }
        if let cap = tokenLimit, cap > 0 {
            return Double(tokens) / Double(cap)
        }
        return 0
    }

    /// Used / limit like "$1.20 / $2.50"; with no limit, just the number of calls.
    var usedText: String {
        if let cap = costLimit, cap > 0 {
            return "\(Format.usd(cost)) / \(Format.usd(cap))"
        }
        if let cap = tokenLimit, cap > 0 {
            return "\(Format.tokens(tokens)) / \(Format.tokens(cap))"
        }
        return "\(Format.count(calls)) 次"
    }

    /// How much is left, using the number the gateway computed; nil when there is no limit.
    var leftText: String? {
        if let cap = costLimit, cap > 0 {
            return "剩余 \(Format.usd(costLeft))"
        }
        if let cap = tokenLimit, cap > 0 {
            return "剩余 \(Format.tokens(tokensLeft))"
        }
        return nil
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        period = try container.decode(String.self, forKey: .period)
        days = try container.decodeIfPresent(Int.self, forKey: .days)
        hours = try container.decodeIfPresent(Int.self, forKey: .hours)
        start = try container.decodeIfPresent(Date.self, forKey: .start) ?? .distantPast
        reset = try container.decodeIfPresent(Date.self, forKey: .reset) ?? .distantPast
        calls = try container.decodeIfPresent(Int.self, forKey: .calls) ?? 0
        tokens = try container.decodeIfPresent(Int.self, forKey: .tokens) ?? 0
        cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        tokenLimit = try container.decodeIfPresent(Int.self, forKey: .tokenLimit)
        costLimit = try container.decodeIfPresent(Double.self, forKey: .costLimit)
        tokensLeft = try container.decodeIfPresent(Int.self, forKey: .tokensLeft) ?? 0
        costLeft = try container.decodeIfPresent(Double.self, forKey: .costLeft) ?? 0
        spent = try container.decodeIfPresent(Bool.self, forKey: .spent) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case period, days, hours, start, reset, calls, tokens, cost
        case tokenLimit, costLimit, tokensLeft, costLeft, spent
    }
}
