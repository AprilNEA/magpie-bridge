import Foundation

/// 网关把一个时段切成的桶（Ledger.Bucket）：今天按小时，7 天 / 30 天按天，更长按周。
nonisolated enum Bucket: String, Sendable {
    case hour, day, week
}

/// 时间轴上的一个桶（usage.SeriesPoint）：这段时间的合计，加上按模型、Agent、提供方拆开的份额。
nonisolated struct SeriesPoint: Decodable, Hashable, Identifiable, Sendable {
    /// 网关在服务器时区里写好的刻度，例如 "Nov 8" 或 "14"；图表直接用它当横轴。
    var label: String
    var time: Date
    var totals: UsageTotals
    /// 维度 → 成员 id → 该成员在这个桶里的量；网关只给整个时段 tokens 最多的 24 个成员。
    var by: [String: [String: SeriesPart]]

    var id: String { label }

    func parts(by dimension: Dimension) -> [String: SeriesPart] {
        by[dimension.rawValue] ?? [:]
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        time = try container.decodeIfPresent(Date.self, forKey: .time) ?? .distantPast
        totals = try UsageTotals(from: decoder)
        by = try container.decodeIfPresent([String: [String: SeriesPart]].self, forKey: .by) ?? [:]
    }

    private enum CodingKeys: CodingKey {
        case label, time, by
    }
}

/// 一个成员在一个桶里的量（usage.Part）。
nonisolated struct SeriesPart: Decodable, Hashable, Sendable {
    var calls = 0
    var tokens = 0
    var cost = 0.0

    init(calls: Int = 0, tokens: Int = 0, cost: Double = 0) {
        self.calls = calls
        self.tokens = tokens
        self.cost = cost
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calls = try container.decodeIfPresent(Int.self, forKey: .calls) ?? 0
        tokens = try container.decodeIfPresent(Int.self, forKey: .tokens) ?? 0
        cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0
    }

    private enum CodingKeys: CodingKey {
        case calls, tokens, cost
    }
}

/// 整个时段里按某个维度汇总的一份（usageapi.Share）：id、给人看的名字和合计。
nonisolated struct UsageShare: Decodable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var totals: UsageTotals

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        if name.isEmpty {
            name = id
        }
        totals = try UsageTotals(from: decoder)
    }

    private enum CodingKeys: CodingKey {
        case id, name
    }
}

/// 把调用拆开看的维度；原始值就是网关 by 里的键。
nonisolated enum Dimension: String, CaseIterable, Identifiable, Sendable {
    case model, agent, provider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model: "模型"
        case .agent: "Agent"
        case .provider: "提供方"
        }
    }
}

/// 图表量的是什么。
nonisolated enum UsageMetric: String, CaseIterable, Identifiable, Sendable {
    case tokens, calls, cost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tokens: "Tokens"
        case .calls: "请求"
        case .cost: "费用"
        }
    }

    func value(of totals: UsageTotals) -> Double {
        switch self {
        case .tokens: Double(totals.tokens)
        case .calls: Double(totals.calls)
        case .cost: totals.cost
        }
    }

    func value(of part: SeriesPart) -> Double {
        switch self {
        case .tokens: Double(part.tokens)
        case .calls: Double(part.calls)
        case .cost: part.cost
        }
    }

    /// 坐标轴和图例上的写法。
    func format(_ value: Double) -> String {
        switch self {
        case .tokens: Format.tokens(Int(value.rounded()))
        case .calls: Format.count(Int(value.rounded()))
        case .cost: Format.usd(value)
        }
    }
}
