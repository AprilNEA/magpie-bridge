import Foundation

/// One page of GET /v1/magpie/usage/requests: a held key only sees its own calls.
nonisolated struct RequestLedger: Decodable, Sendable {
    var period: String
    var rows: [RequestRow]
    var offset: Int
    /// The total row count after filtering, sent with every page.
    var total: Int
    /// The totals for the whole time window, flattened into the same object as rows.
    var totals: UsageTotals
    /// The whole time window's series, cut by bucket; sent with every page, unrelated to paging.
    var bucket: Bucket
    var series: [SeriesPoint]
    /// The whole time window's shares summed by dimension (the raw value of Dimension), with the
    /// most tokens first. For the dimension a filter selects, the shares are computed without that
    /// filter, so the other options stay available while switching.
    var by: [String: [UsageShare]]
    /// Agents and providers that had calls in this time window, for the filter; a held key only
    /// sees the ones it used.
    var agents: [Named]
    var providers: [Named]

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
        agents = try container.decodeIfPresent([Named].self, forKey: .agents) ?? []
        providers = try container.decodeIfPresent([Named].self, forKey: .providers) ?? []
    }

    private enum CodingKeys: CodingKey {
        case period, rows, offset, total, bucket, series, by, agents, providers
    }
}

/// One Agent or provider among the filter options (usageapi.Named): id and display name.
nonisolated struct Named: Decodable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.name = name.isEmpty ? id : name
    }

    private enum CodingKeys: CodingKey {
        case id, name
    }
}

/// One call (usage.Row plus the names the page displays). The gateway gives no row id, so one is
/// generated locally.
nonisolated struct RequestRow: Decodable, Hashable, Identifiable, Sendable {
    let id = UUID()
    var time: Date
    var agent: String
    var agentName: String
    var provider: String
    var providerName: String
    /// The provider's model id; empty for calls the gateway never forwarded.
    var model: String
    /// The model the Agent requested; if it differs from model, the call was rewritten or routed.
    var requested: String?
    var served: String?
    var endpoint: String?
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var reasoning: Int
    var millis: Int64
    /// The HTTP status returned to the Agent; a call read from a session file has none and is 0.
    var status: Int
    var error: String?
    /// The type name the provider gave the error, for example rate_limit_error.
    var errorType: String?
    /// Rejected by the gateway itself, never sent to any provider.
    var rejected: Bool
    /// This try failed and the gateway handed on to the next try; the Agent did not receive this
    /// error, and the totals do not count it as a call.
    var handedOn: Bool
    /// How many providers / times the gateway tried for this request; the gateway leaves it out
    /// after a single try, so 0.
    var tries: Int
    /// The upstream host actually connected to.
    var host: String?
    /// The bytes actually sent to the provider and received back.
    var upBytes: Int64
    var downBytes: Int64
    var cost: Double
    /// Only when the model has a known price does cost mean anything.
    var priced: Bool
    /// Canceled by the Agent itself; not counted as failed.
    var canceled: Bool

    var tokens: Int { input + output + cacheRead + cacheWrite }

    /// usage.Record.Failed: returned an error status or recorded an error, and was not canceled by
    /// the Agent itself.
    var failed: Bool {
        (status >= 400 || !(error ?? "").isEmpty) && !canceled
    }

    /// usage.Record.IsRejected: rows carrying the flag, plus rows written before the flag existed
    /// that returned an error without being sent to a provider.
    var isRejected: Bool {
        rejected || (provider.isEmpty && status >= 400)
    }

    /// The model name shown in the list: the one actually used, otherwise the one requested.
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
        errorType = try container.decodeIfPresent(String.self, forKey: .errorType)
        rejected = try container.decodeIfPresent(Bool.self, forKey: .rejected) ?? false
        handedOn = try container.decodeIfPresent(Bool.self, forKey: .handedOn) ?? false
        tries = try container.decodeIfPresent(Int.self, forKey: .tries) ?? 0
        host = try container.decodeIfPresent(String.self, forKey: .host)
        upBytes = try container.decodeIfPresent(Int64.self, forKey: .upBytes) ?? 0
        downBytes = try container.decodeIfPresent(Int64.self, forKey: .downBytes) ?? 0
        cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        priced = try container.decodeIfPresent(Bool.self, forKey: .priced) ?? false
        canceled = try container.decodeIfPresent(Bool.self, forKey: .canceled) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case time = "t"
        case agent, agentName, provider, providerName, model, served, status, cost, priced
        case canceled, rejected, tries, host
        case requested = "req"
        case endpoint = "ep"
        case input = "in"
        case output = "out"
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case reasoning
        case millis = "ms"
        case error = "err"
        case errorType = "err_type"
        case handedOn = "handed_on"
        case upBytes = "up_bytes"
        case downBytes = "down_bytes"
    }
}
