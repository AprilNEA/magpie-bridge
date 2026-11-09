import Foundation

/// The bucket the gateway cuts a period into (Ledger.Bucket): today by hour, 7 / 30 days by day,
/// anything longer by week.
nonisolated enum Bucket: String, Sendable {
    case hour, day, week
}

/// One bucket on the series (usage.SeriesPoint): the totals for that span, plus the shares broken
/// down by model, Agent, and provider.
nonisolated struct SeriesPoint: Decodable, Hashable, Identifiable, Sendable {
    /// The tick the gateway writes in the server's time zone, for example "Nov 8" or "14"; the
    /// chart uses it directly as the x axis.
    var label: String
    var time: Date
    var totals: UsageTotals
    /// Dimension → member id → that member's amount in this bucket; the gateway only sends the 24
    /// members with the most tokens over the whole period.
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

/// One member's amount in one bucket (usage.Part).
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

/// One share of the whole period summed by a dimension (usageapi.Share): id, display name, and
/// totals.
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

/// A dimension to break calls down by; the raw value is the key in the gateway's by field.
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

/// What the chart measures.
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

    /// Amounts smaller than this count as nothing. Tokens and counts are integers; the gateway
    /// rounds cost to four decimal places, so a few members added together can differ from the
    /// totals by a few ten-thousandths; a difference under a thousandth of a dollar is rounding,
    /// not anyone's usage.
    var resolution: Double {
        switch self {
        case .tokens, .calls: 1
        case .cost: 0.001
        }
    }

    /// The form used on the axis and in the legend.
    func format(_ value: Double) -> String {
        switch self {
        case .tokens: Format.tokens(Int(value.rounded()))
        case .calls: Format.count(Int(value.rounded()))
        case .cost: Format.usd(value)
        }
    }
}
