import Foundation

/// 发请求的东西：App 用 URLSession，测试用假的。
nonisolated protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

nonisolated extension URLSession: Transport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// 网关拒绝或没有回答的原因。文案和网页 /me 的一致。
nonisolated enum MagpieError: Error, Equatable, Sendable {
    /// 401：不是这个网关启用中的密钥。
    case invalidKey
    /// 403 而且不是 gateway_key_held：网关没有开放给远程调用。
    case notShared
    /// 403 gateway_key_held：受限密钥不能看这个端点。
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

/// 网关的错误体：{"error":{"message","type","code","param"}}。
nonisolated struct APIErrorBody: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        var message: String?
        var type: String?
        var code: String?
    }

    var error: Detail
}

/// 用一把网关密钥调用 /v1/magpie/* 这些密钥自己能看的端点。
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

    /// 一页请求记录，最新的在前；limit 最大 500。
    func requests(
        period: UsagePeriod, offset: Int = 0, limit: Int = 100
    ) async throws(MagpieError) -> RequestLedger {
        try await get(
            "v1/magpie/usage/requests",
            query: [
                URLQueryItem(name: "period", value: period.rawValue),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
            ])
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

/// Go 用 RFC3339Nano 写时间：小数位 0 到 9 位，零值是公元 1 年。
nonisolated enum RFC3339 {
    static func date(from text: String) -> Date? {
        var text = text
        if let dot = text.firstIndex(of: "."),
            let end = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" })
        {
            // ISO8601DateFormatter 只认恰好三位小数。
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
