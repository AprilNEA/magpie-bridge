/// The totals of a set of calls (usage.Totals). Each endpoint guarantees only the basic fields;
/// the rest default to 0.
nonisolated struct UsageTotals: Decodable, Hashable, Sendable {
    var calls = 0
    var errors = 0
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var reasoning = 0
    /// In US dollars, over the calls that have a price.
    var cost = 0.0
    /// Calls that have tokens but no known price.
    var unpriced = 0

    /// The token count the /me web page shows: the four kinds added together.
    var tokens: Int { input + output + cacheRead + cacheWrite }

    /// Prompt tokens sent to the model: input that missed the cache, plus cache reads and writes.
    var promptTokens: Int { input + cacheRead + cacheWrite }

    /// The fraction of prompt tokens read from the cache, 0 to 1; nil when there is no prompt.
    var cacheHitRate: Double? {
        promptTokens > 0 ? Double(cacheRead) / Double(promptTokens) : nil
    }

    /// Failed calls as a fraction of all calls; nil when there are no calls.
    var errorRate: Double? {
        calls > 0 ? Double(errors) / Double(calls) : nil
    }

    /// The average cost per call, over all calls; nil when there are no calls.
    var averageCost: Double? {
        calls > 0 ? cost / Double(calls) : nil
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calls = try container.decodeIfPresent(Int.self, forKey: .calls) ?? 0
        errors = try container.decodeIfPresent(Int.self, forKey: .errors) ?? 0
        input = try container.decodeIfPresent(Int.self, forKey: .input) ?? 0
        output = try container.decodeIfPresent(Int.self, forKey: .output) ?? 0
        cacheRead = try container.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
        cacheWrite = try container.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
        reasoning = try container.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
        cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        unpriced = try container.decodeIfPresent(Int.self, forKey: .unpriced) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case calls, errors, input, output, reasoning, cost, unpriced
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }
}

/// The four kinds of tokens; the tokens on the /me web page are these four added together.
nonisolated enum TokenKind: String, CaseIterable, Identifiable, Sendable {
    case input, output, cacheRead, cacheWrite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .input: "输入"
        case .output: "输出"
        case .cacheRead: "缓存读取"
        case .cacheWrite: "缓存写入"
        }
    }

    func value(of totals: UsageTotals) -> Int {
        switch self {
        case .input: totals.input
        case .output: totals.output
        case .cacheRead: totals.cacheRead
        case .cacheWrite: totals.cacheWrite
        }
    }
}
