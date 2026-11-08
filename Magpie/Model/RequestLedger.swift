import Foundation

/// GET /v1/magpie/usage/requests 的一页：受限密钥只会看到自己的调用。
nonisolated struct RequestLedger: Decodable, Sendable {
    var period: String
    var rows: [RequestRow]
    var offset: Int
    /// 筛选后的总行数，每页都带。
    var total: Int
    /// 整个时间窗口的合计，和 rows 平铺在同一个对象里。
    var totals: UsageTotals
    /// 整个时间窗口按 bucket 切开的时间轴，每页都带，和翻页无关。
    var bucket: Bucket
    var series: [SeriesPoint]
    /// 整个时间窗口按维度（Dimension 的原始值）汇总的份额，tokens 多的在前。
    var by: [String: [UsageShare]]

    func shares(by dimension: Dimension) -> [UsageShare] {
        by[dimension.rawValue] ?? []
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        period = try container.decodeIfPresent(String.self, forKey: .period) ?? ""
        rows = try container.decodeIfPresent([RequestRow].self, forKey: .rows) ?? []
        offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        totals = try UsageTotals(from: decoder)
        let bucketName = try container.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        bucket = Bucket(rawValue: bucketName) ?? .day
        series = try container.decodeIfPresent([SeriesPoint].self, forKey: .series) ?? []
        by = try container.decodeIfPresent([String: [UsageShare]].self, forKey: .by) ?? [:]
    }

    private enum CodingKeys: CodingKey {
        case period, rows, offset, total, bucket, series, by
    }
}

/// 一次调用（usage.Row 加上页面显示用的名字）。网关不给行 id，这里本地生成。
nonisolated struct RequestRow: Decodable, Hashable, Identifiable, Sendable {
    let id = UUID()
    var time: Date
    var agent: String
    var agentName: String
    var provider: String
    var providerName: String
    /// 供应商的模型 id；网关没转发出去的调用为空。
    var model: String
    /// Agent 请求的模型，和 model 不同时表示被改写或路由。
    var requested: String?
    var served: String?
    var endpoint: String?
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var reasoning: Int
    var millis: Int64
    /// 回给 Agent 的 HTTP 状态；从会话文件读来的调用没有，为 0。
    var status: Int
    var error: String?
    var cost: Double
    /// 模型有已知价格，cost 才有意义。
    var priced: Bool
    /// Agent 自己取消的，不算失败。
    var canceled: Bool

    var tokens: Int { input + output + cacheRead + cacheWrite }

    /// usage.Record.Failed：回了错误状态或记了错误，且不是 Agent 自己取消。
    var failed: Bool {
        (status >= 400 || !(error ?? "").isEmpty) && !canceled
    }

    /// 列表里显示的模型名：实际用的，否则请求的。
    var displayModel: String {
        model.isEmpty ? (requested ?? "—") : model
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(Date.self, forKey: .time)
        agent = try container.decodeIfPresent(String.self, forKey: .agent) ?? ""
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName) ?? ""
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        requested = try container.decodeIfPresent(String.self, forKey: .requested)
        served = try container.decodeIfPresent(String.self, forKey: .served)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        input = try container.decodeIfPresent(Int.self, forKey: .input) ?? 0
        output = try container.decodeIfPresent(Int.self, forKey: .output) ?? 0
        cacheRead = try container.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
        cacheWrite = try container.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
        reasoning = try container.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
        millis = try container.decodeIfPresent(Int64.self, forKey: .millis) ?? 0
        status = try container.decodeIfPresent(Int.self, forKey: .status) ?? 0
        error = try container.decodeIfPresent(String.self, forKey: .error)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        priced = try container.decodeIfPresent(Bool.self, forKey: .priced) ?? false
        canceled = try container.decodeIfPresent(Bool.self, forKey: .canceled) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case time = "t"
        case agent, agentName, provider, providerName, model, served, status, cost, priced
        case canceled
        case requested = "req"
        case endpoint = "ep"
        case input = "in"
        case output = "out"
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case reasoning
        case millis = "ms"
        case error = "err"
    }
}
