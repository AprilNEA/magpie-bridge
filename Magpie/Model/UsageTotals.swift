/// 一组调用的合计（usage.Totals）。各端点只保证基础字段，其余缺省为 0。
nonisolated struct UsageTotals: Decodable, Hashable, Sendable {
    var calls = 0
    var errors = 0
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var reasoning = 0
    /// 美元，按有价格的调用算。
    var cost = 0.0
    /// 有 token 但不知道价格的调用数。
    var unpriced = 0

    /// 网页 /me 显示的 token 数：四类相加。
    var tokens: Int { input + output + cacheRead + cacheWrite }

    /// 发给模型的提示词 tokens：没命中缓存的输入，加上缓存读取和写入。
    var promptTokens: Int { input + cacheRead + cacheWrite }

    /// 提示词 tokens 里从缓存读出来的比例，0 到 1；没有提示词时为 nil。
    var cacheHitRate: Double? {
        promptTokens > 0 ? Double(cacheRead) / Double(promptTokens) : nil
    }

    /// 失败的调用占全部调用的比例；没有调用时为 nil。
    var errorRate: Double? {
        calls > 0 ? Double(errors) / Double(calls) : nil
    }

    /// 平均每次调用的费用，按全部调用算；没有调用时为 nil。
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

/// tokens 的四类；网页 /me 的 tokens 就是这四项加起来。
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
