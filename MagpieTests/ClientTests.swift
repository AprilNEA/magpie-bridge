import Foundation
import Testing

@testable import Magpie

@Suite struct ClientTests {
    private let base = URL(string: "https://magpie.example.com")!

    @Test func sendsBearerKeyToMagpieMe() async throws {
        let transport = try FakeTransport(.init(200, fixture("me")))
        let client = MagpieClient(baseURL: base, key: "sk-magpie-key-test", transport: transport)
        let info = try await client.me()
        #expect(info.name == "staff-test")

        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://magpie.example.com/v1/magpie/me")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-magpie-key-test")
        #expect(request.httpMethod == "GET")
    }

    @Test func requestsPageCarriesPeriodAndOffset() async throws {
        let transport = try FakeTransport(.init(200, fixture("requests")))
        let client = MagpieClient(baseURL: base, key: "k", transport: transport)
        let ledger = try await client.requests(period: .week, offset: 100, limit: 50)
        #expect(ledger.rows.count == 5)

        let url = try #require(await transport.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.path == "/v1/magpie/usage/requests")
        #expect(query == ["period": "7d", "offset": "100", "limit": "50"])
    }

    /// Filters go into the query string only when set, and whitespace around the search term does
    /// not count; unset filters are left out so the gateway applies its defaults.
    @Test func requestsPageCarriesOnlyTheFiltersSet() async throws {
        let transport = try FakeTransport(.init(200, fixture("requests")))
        let client = MagpieClient(baseURL: base, key: "k", transport: transport)
        var filter = RequestFilter()
        filter.failed = true
        filter.model = "deepseek-v4-flash"
        filter.query = "  codex "
        _ = try await client.requests(period: .today, filter: filter)

        let url = try #require(await transport.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(
            query == [
                "period": "today", "offset": "0", "limit": "100",
                "failed": "1", "model": "deepseek-v4-flash", "q": "codex",
            ])
    }

    @Test func requestFilterTracksWhatIsSet() {
        var filter = RequestFilter()
        #expect(filter.isEmpty)
        filter.query = "   "
        #expect(filter.isEmpty)
        #expect(filter.queryItems.isEmpty)
        filter.agent = "codex"
        filter.failed = true
        #expect(filter.activeFields == [.failed, .agent])
        filter.clear(.failed)
        #expect(filter.activeFields == [.agent])
        #expect(filter.queryItems == [URLQueryItem(name: "agent", value: "codex")])
    }

    @Test func limitDecodesHeldTo() async throws {
        let transport = try FakeTransport(.init(200, fixture("limit")))
        let client = MagpieClient(baseURL: base, key: "k", transport: transport)
        let limit = try await client.limit()
        #expect(limit.heldTo == ["budget", "models"])
    }

    @Test func statusCodesMapToGatewayErrors() {
        let held = """
            {"error":{"message":"this key only sees its own usage","type":"permission_error",
            "code":"gateway_key_held","param":null}}
            """
        let boom = #"{"error":{"message":"boom","type":"api_error","code":null,"param":null}}"#
        #expect(MagpieClient.failure(status: 401, body: Data()) == .invalidKey)
        #expect(
            MagpieClient.failure(status: 403, body: Data(held.utf8))
                == .held("this key only sees its own usage"))
        #expect(MagpieClient.failure(status: 403, body: Data(boom.utf8)) == .notShared)
        #expect(MagpieClient.failure(status: 429, body: Data()) == .tooManyAttempts)
        #expect(
            MagpieClient.failure(status: 500, body: Data(boom.utf8))
                == .server(status: 500, message: "boom"))
        #expect(
            MagpieClient.failure(status: 502, body: Data("<html>".utf8))
                == .server(status: 502, message: nil))
    }

    @Test func unauthorizedThrowsInvalidKey() async throws {
        let transport = FakeTransport(.init(401, json: #"{"error":{"message":"nope"}}"#))
        let client = MagpieClient(baseURL: base, key: "k", transport: transport)
        await #expect(throws: MagpieError.invalidKey) {
            try await client.me()
        }
    }

    @Test func unreadableBodyIsDecodingError() async throws {
        let transport = FakeTransport(.init(200, json: "[]"))
        let client = MagpieClient(baseURL: base, key: "k", transport: transport)
        do {
            _ = try await client.me()
            Issue.record("应当抛错")
        } catch {
            guard case .decoding = error else {
                Issue.record("应当是 decoding，实际是 \(error)")
                return
            }
        }
    }

    @Test func transportFailureIsNetworkError() async throws {
        let transport = FakeTransport()
        let client = MagpieClient(baseURL: base, key: "k", transport: transport)
        do {
            _ = try await client.me()
            Issue.record("应当抛错")
        } catch {
            guard case .network = error else {
                Issue.record("应当是 network，实际是 \(error)")
                return
            }
        }
    }

    @Test(arguments: [
        ("magpie.example.com", "https://magpie.example.com"),
        ("https://magpie.example.com/me", "https://magpie.example.com"),
        ("https://magpie.example.com/v1/", "https://magpie.example.com"),
        ("  http://localhost:3425/me?x=1#top ", "http://localhost:3425"),
        ("https://proxy.example.com/magpie/v1", "https://proxy.example.com/magpie"),
    ])
    func gatewayAddressNormalizes(text: String, expected: String) {
        #expect(Credential.gatewayURL(from: text)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "ftp://magpie.example.com", "https://", "not a url"])
    func gatewayAddressRejects(text: String) {
        #expect(Credential.gatewayURL(from: text) == nil)
    }
}
