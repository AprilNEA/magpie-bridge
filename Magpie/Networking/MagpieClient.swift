import Foundation

/// Whatever sends requests: the app uses URLSession, tests use a fake.
nonisolated protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

nonisolated extension URLSession: Transport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Why the gateway rejected the request or did not answer. The wording matches the web /me page.
nonisolated enum MagpieError: Error, Equatable, Sendable {
    /// 401: not an enabled key on this gateway.
    case invalidKey
    /// 403 without gateway_key_held: the gateway is not open to remote calls.
    case notShared
    /// 403 gateway_key_held: a held key may not see this endpoint.
    case held(String)
    /// 429
    case tooManyAttempts
    case server(status: Int, message: String?)
    case network(String)
    case decoding(String)
}

nonisolated extension MagpieError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidKey: "这不是这个网关可用的密钥。请向发给你密钥的人确认。"
        case .notShared: "这个网关目前没有共享。"
        case .held(let message): message.isEmpty ? "这把密钥不能查看这项内容。" : message
        case .tooManyAttempts: "尝试次数过多，请等一分钟再试。"
        case .server(let status, let message):
            message.map { "网关返回 \(status)：\($0)" } ?? "网关返回 \(status)。"
        case .network: "网关没有响应。请检查地址后重试。"
        case .decoding: "读不懂网关的回复，可能需要更新 App 或网关。"
        }
    }
}

/// The gateway's error body: {"error":{"message","type","code","param"}}.
nonisolated struct APIErrorBody: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        var message: String?
        var type: String?
        var code: String?
    }

    var error: Detail
}

/// Calls /v1/magpie/*, the endpoints a key can see for itself, with one gateway key.
nonisolated struct MagpieClient: Sendable {
    static let heldCode = "gateway_key_held"

    let baseURL: URL
    let key: String
    let transport: any Transport

    init(baseURL: URL, key: String, transport: any Transport = URLSession.shared) {
        self.baseURL = baseURL
        self.key = key
        self.transport = transport
    }

    func me() async throws(MagpieError) -> KeyInfo {
        try await get("v1/magpie/me")
    }

    func limit() async throws(MagpieError) -> KeyLimit {
        try await get("v1/magpie/limit")
    }

    /// One page of request records, newest first; limit is at most 500. The totals, series, and
    /// shares cover the whole filtered period and come with every page. Days and hours split by
    /// the gateway machine's time zone: this route does not accept ?tz=.
    func requests(
        period: UsagePeriod, filter: RequestFilter = RequestFilter(), offset: Int = 0,
        limit: Int = 100
    ) async throws(MagpieError) -> RequestLedger {
        try await requests(period: period.rawValue, filter: filter, offset: offset, limit: limit)
    }

    /// The same page over days the reader picked. The gateway reads the dates in its own time zone
    /// and cuts 2 to 60 days into one point per day; a gateway too old to know picked ranges
    /// answers for 30 days instead.
    func requests(
        days: DayRange, filter: RequestFilter = RequestFilter(), offset: Int = 0, limit: Int = 100
    ) async throws(MagpieError) -> RequestLedger {
        try await requests(period: days.query, filter: filter, offset: offset, limit: limit)
    }

    /// The last 53 weeks a day each: the ranges Heatmap cuts the span into, fetched at once with
    /// one row each, since only their series matter.
    func heatmap(
        through today: Date = .now, calendar: Calendar = .current
    ) async throws(MagpieError) -> Heatmap {
        typealias Fetched = Result<[SeriesPoint], MagpieError>
        let ranges = Heatmap.ranges(through: today, calendar: calendar)
        let fetched = await withTaskGroup(of: (Int, Fetched).self) { group in
            for (index, range) in ranges.enumerated() {
                group.addTask {
                    do throws(MagpieError) {
                        return (index, .success(try await requests(days: range, limit: 1).series))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var out = Array(repeating: Fetched.success([]), count: ranges.count)
            for await (index, result) in group {
                out[index] = result
            }
            return out
        }
        var series: [[SeriesPoint]] = []
        for result in fetched {
            series.append(try result.get())
        }
        return try Heatmap(ranges: ranges, series: series, calendar: calendar)
    }

    private func requests(
        period: String, filter: RequestFilter, offset: Int, limit: Int
    ) async throws(MagpieError) -> RequestLedger {
        try await get(
            "v1/magpie/usage/requests",
            query: [
                URLQueryItem(name: "period", value: period),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
            ] + filter.queryItems)
    }

    func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        return request
    }

    private func get<T: Decodable>(
        _ path: String, query: [URLQueryItem] = []
    ) async throws(MagpieError) -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(request(path, query: query))
        } catch {
            throw .network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.failure(status: status, body: data)
        }
        do {
            return try MagpieJSON.decoder().decode(T.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
    }

    static func failure(status: Int, body: Data) -> MagpieError {
        let detail = try? JSONDecoder().decode(APIErrorBody.self, from: body).error
        switch status {
        case 401: return .invalidKey
        case 403 where detail?.code == heldCode: return .held(detail?.message ?? "")
        case 403: return .notShared
        case 429: return .tooManyAttempts
        default: return .server(status: status, message: detail?.message)
        }
    }
}

nonisolated enum MagpieJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = RFC3339.date(from: text) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "不是 RFC 3339 时间：\(text)"))
            }
            return date
        }
        return decoder
    }
}

/// Go writes times as RFC3339Nano: 0 to 9 fractional digits, and the zero value is year 1 AD.
nonisolated enum RFC3339 {
    static func date(from text: String) -> Date? {
        var text = text
        if let dot = text.firstIndex(of: "."),
            let end = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" })
        {
            // ISO8601DateFormatter only accepts exactly three fractional digits.
            let digits = text[text.index(after: dot)..<end].prefix(3)
            let padded = digits + String(repeating: "0", count: 3 - digits.count)
            text.replaceSubrange(dot..<end, with: digits.isEmpty ? "" : "." + padded)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions =
            text.contains(".")
            ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
