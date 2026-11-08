import Foundation
import Testing

@testable import Magpie

private final class FixtureMarker {}

/// MagpieTests/Fixtures 里本地网关（v0.1.3314）的真实响应。
func fixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle(for: FixtureMarker.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

/// 按顺序回放预先写好的响应，并记下收到的请求。
actor FakeTransport: Transport {
    struct Reply {
        var status: Int
        var body: Data

        init(_ status: Int, _ body: Data = Data()) {
            self.status = status
            self.body = body
        }

        init(_ status: Int, json: String) {
            self.init(status, Data(json.utf8))
        }
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: Reply...) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty, let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: replies[0].status, httpVersion: nil, headerFields: nil)
        else {
            throw URLError(.cannotConnectToHost)
        }
        return (replies.removeFirst().body, response)
    }
}

/// 内存里的钥匙串；failWith 不为空时每次操作都失败。
final class MemoryKeychain: KeychainItems {
    var items: [String: Data] = [:]
    var failWith: OSStatus?

    func read(account: String) throws(KeychainFailure) -> Data? {
        try check()
        return items[account]
    }

    func write(_ data: Data, account: String) throws(KeychainFailure) {
        try check()
        items[account] = data
    }

    func delete(account: String) throws(KeychainFailure) {
        try check()
        items[account] = nil
    }

    private func check() throws(KeychainFailure) {
        if let failWith {
            throw KeychainFailure(status: failWith)
        }
    }
}

func scratchDefaults() throws -> UserDefaults {
    let name = "com.aprilnea.magpie.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return defaults
}
