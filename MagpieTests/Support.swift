import Foundation
import Testing

@testable import Magpie

private final class FixtureMarker {}

/// Real responses from a local gateway (v0.1.3314), kept in MagpieTests/Fixtures.
func fixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle(for: FixtureMarker.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

/// Replays prepared responses in order and records the requests received.
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

/// An in-memory Keychain; when failWith is set, every operation fails.
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
    let name = "com.aprilnea.queqiao.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return defaults
}
