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
