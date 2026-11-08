import Foundation

/// 密钥的一条额度及其当前窗口的用量（budget.Status）。
nonisolated struct LimitStatus: Decodable, Hashable, Identifiable, Sendable {
    /// day、week、month，或 days、hours 配合 days / hours 的数量。
    var period: String
    var days: Int?
    var hours: Int?
    var start: Date
    /// 窗口何时重置；Go 的零值（公元 1 年）表示没有。
    var reset: Date
    var calls: Int
    var tokens: Int
    var cost: Double
    var tokenLimit: Int?
    var costLimit: Double?
    var tokensLeft: Int
    var costLeft: Double
    /// 已用完，到重置前都会被拒。
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
