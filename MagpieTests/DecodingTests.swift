import Foundation
import Testing

@testable import Magpie

@Suite struct DecodingTests {
    @Test func keyInfoFromGateway() throws {
        let info = try MagpieJSON.decoder().decode(KeyInfo.self, from: fixture("me"))
        #expect(info.name == "staff-test")
        #expect(!info.readOnly)
        #expect(info.version == "0.1.3314")

        #expect(info.limits.map(\.title) == ["每 5 小时", "每周"])
        #expect(info.limits[0].costLimit == 50)
        #expect(info.limits[0].tokenLimit == nil)
        #expect(info.limits[0].calls == 4)
        #expect(!info.limits[0].spent)
        #expect(info.limits[1].resetsAt != nil)

        #expect(info.totals(for: .today).calls == 4)
        #expect(info.totals(for: .today).errors == 4)
        #expect(info.totals(for: .month).tokens == 0)
        #expect(info.totals(for: .all).calls == 0)

        #expect(
            info.topModels.map(\.id) == ["deepseek-v4-flash", "deepseek-flash", "deepseek-v4-pro"])
        #expect(info.topModels[0].totals.calls == 2)
        #expect(info.models.map(\.id).contains("deepseek/deepseek-v4-flash"))
    }

    /// topModels 里没有 provider/ 前缀，要和 models 里带前缀的 id 对上。
    @Test func suggestedModelMatchesTopModelBySuffix() throws {
        let info = try MagpieJSON.decoder().decode(KeyInfo.self, from: fixture("me"))
        #expect(info.suggestedModel?.id == "deepseek/deepseek-v4-flash")
    }

    @Test func suggestedModelFallsBackToFirstAllowed() throws {
        let json = """
            {"name":"k","topModels":[{"id":"gpt-5","calls":9}],
             "models":[{"id":"claude/claude-opus-5","label":"Opus 5"},{"id":"codex/gpt-5.5"}]}
            """
        let info = try MagpieJSON.decoder().decode(KeyInfo.self, from: Data(json.utf8))
        #expect(info.suggestedModel?.id == "claude/claude-opus-5")
        #expect(info.models[1].label == "codex/gpt-5.5")
        #expect(info.limits.isEmpty)
    }

    /// 缓存命中按提示词（输入加缓存读写）算，失败率和平均每次按全部调用算。
    @Test func usageTotalsRatesAndTokenKinds() throws {
        let json = """
            {"calls":8,"errors":2,"input":100,"output":50,"cache_read":300,"cache_write":100,
             "cost":0.4}
            """
        let totals = try MagpieJSON.decoder().decode(UsageTotals.self, from: Data(json.utf8))
        #expect(totals.tokens == 550)
        #expect(totals.promptTokens == 500)
        #expect(abs((totals.cacheHitRate ?? 0) - 0.6) < 1e-9)
        #expect(abs((totals.errorRate ?? 0) - 0.25) < 1e-9)
        #expect(abs((totals.averageCost ?? 0) - 0.05) < 1e-9)
        #expect(TokenKind.allCases.map { $0.value(of: totals) } == [100, 50, 300, 100])

        // 全失败、一个 token 都没有：有失败率，没有缓存命中。
        let failed = try MagpieJSON.decoder().decode(
            UsageTotals.self, from: Data(#"{"calls":3,"errors":3}"#.utf8))
        #expect(failed.cacheHitRate == nil)
        #expect(failed.errorRate == 1)
        #expect(failed.averageCost == 0)
        #expect(UsageTotals().errorRate == nil)
        #expect(UsageTotals().averageCost == nil)
    }

    @Test func limitStatusTitlesAndZeroReset() throws {
        let json = """
            [{"period":"day","reset":"0001-01-01T00:00:00Z","tokens":12,"tokenLimit":100,"spent":true},
             {"period":"days","days":3,"reset":"2026-11-10T00:00:00Z"},
             {"period":"month"}]
            """
        let limits = try MagpieJSON.decoder().decode([LimitStatus].self, from: Data(json.utf8))
        #expect(limits.map(\.title) == ["每天", "每 3 天", "每月"])
        #expect(limits[0].resetsAt == nil)
        #expect(limits[0].spent)
        #expect(limits[0].tokenLimit == 100)
        #expect(limits[1].resetsAt != nil)
        #expect(limits[2].resetsAt == nil)
    }

    @Test func keyLimitFromGateway() throws {
        let limit = try MagpieJSON.decoder().decode(KeyLimit.self, from: fixture("limit"))
        #expect(limit.limited)
        #expect(limit.key == "staff-test")
        #expect(limit.heldToTitles == ["额度", "模型"])
        #expect(limit.models == ["claude/*", "codex/*", "deepseek/*"])
        #expect(limit.limits.map(\.title) == ["每 5 小时", "每周"])
        #expect(limit.expires == nil)
        // 网关只在有的时候才给这些字段：没有就是不可见配额、全部 MCP、没有签发者。
        #expect(!limit.quotas)
        #expect(limit.quotaProviders.isEmpty)
        #expect(limit.mcpAccess == .every)
        #expect(limit.issuerLimits.isEmpty)
    }

    @Test func keyLimitWithIssuerQuotasAndMCP() throws {
        let json = """
            {"limited":false,"key":"issued","heldTo":["accounts"],"quotas":true,
             "quotaProviders":["claude","codex"],"mcp":["github","web-search/search"],
             "issuerLimits":[{"period":"month","cost":120.5,"costLimit":300,"costLeft":179.5}],
             "expires":"2027-01-01T00:00:00Z"}
            """
        let limit = try MagpieJSON.decoder().decode(KeyLimit.self, from: Data(json.utf8))
        #expect(limit.heldToTitles == ["账号"])
        #expect(limit.quotas)
        #expect(limit.quotaProviders == ["claude", "codex"])
        #expect(limit.mcpAccess == .some(["github", "web-search/search"]))
        #expect(limit.issuerLimits.map(\.title) == ["每月"])
        #expect(limit.issuerLimits[0].costLeft == 179.5)
        #expect(limit.expires != nil)
    }

    /// 只有一个 "-" 是一个 MCP 都不能用；不是空列表那种「全部」。
    @Test func keyLimitMCPDashMeansNone() throws {
        let json = #"{"limited":false,"key":"k","mcp":["-"]}"#
        let limit = try MagpieJSON.decoder().decode(KeyLimit.self, from: Data(json.utf8))
        #expect(limit.mcpAccess == .none)
    }

    /// 费用上限优先于 tokens 上限；用完了不管比例都算满；剩余用网关算好的数。
    @Test func limitStatusUsageFollowsCostFirst() throws {
        let json = """
            [{"period":"day","cost":1.2,"costLimit":2.5,"costLeft":1.3,
              "tokens":900,"tokenLimit":1000,"tokensLeft":100,"calls":7},
             {"period":"day","tokens":250,"tokenLimit":1000,"tokensLeft":750},
             {"period":"day","cost":0.5,"costLimit":2.5,"costLeft":2,"spent":true},
             {"period":"day","calls":3}]
            """
        let limits = try MagpieJSON.decoder().decode([LimitStatus].self, from: Data(json.utf8))
        #expect(abs(limits[0].usedFraction - 0.48) < 1e-9)
        #expect(limits[0].usedText == "$1.20 / $2.50")
        #expect(limits[0].leftText == "剩余 $1.30")
        #expect(limits[1].usedFraction == 0.25)
        #expect(limits[1].usedText == "\(Format.tokens(250)) / \(Format.tokens(1000))")
        #expect(limits[1].leftText == "剩余 \(Format.tokens(750))")
        #expect(limits[2].usedFraction == 1)
        #expect(limits[3].usedFraction == 0)
        #expect(limits[3].usedText == "3 次")
        #expect(limits[3].leftText == nil)
    }

    @Test func requestLedgerFromGateway() throws {
        let ledger = try MagpieJSON.decoder().decode(RequestLedger.self, from: fixture("requests"))
        #expect(ledger.total == 5)
        #expect(ledger.offset == 0)
        #expect(ledger.rows.count == 5)
        // 被网关直接拒绝的 404 不算一次调用，所以合计是 4。
        #expect(ledger.totals.calls == 4)
        #expect(ledger.totals.errors == 4)

        // 筛选菜单用的列表：受限密钥只看到自己用过的 Agent 和提供方。
        #expect(ledger.agents.map(\.name) == ["Claude Code", "Codex"])
        #expect(ledger.providers.map(\.id) == ["deepseek"])

        let rejected = ledger.rows[0]
        #expect(rejected.status == 404)
        #expect(rejected.error == "unknown model")
        #expect(rejected.agent == "curl")
        #expect(rejected.failed)
        #expect(rejected.rejected)
        #expect(rejected.isRejected)
        #expect(!rejected.handedOn)
        #expect(!rejected.canceled)
        #expect(rejected.errorType == nil)
        #expect(rejected.host == nil)
        #expect(rejected.displayModel == "openai/gpt-5")

        let upstream = ledger.rows[1]
        #expect(upstream.agentName == "Codex")
        #expect(upstream.providerName == "DeepSeek")
        #expect(upstream.endpoint == "/v1/messages")
        #expect(upstream.requested == "deepseek/deepseek-v4-flash")
        #expect(upstream.model == "deepseek-v4-flash")
        #expect(upstream.millis == 267)
        #expect(!upstream.priced)
        #expect(upstream.failed)
        #expect(!upstream.rejected)
        #expect(!upstream.isRejected)
        #expect(upstream.errorType == "authentication_error")
        #expect(upstream.host == "api.deepseek.com")
        #expect(upstream.upBytes == 120)
        #expect(upstream.downBytes == 204)
        // 只试了一次时网关不写 tries。
        #expect(upstream.tries == 0)
    }

    /// 老账本里被拒绝的行没有 rejected 标记：没发给提供方就回了 4xx 的也算网关拒绝（usage.Record.IsRejected）。
    /// 失败后被转给下一次尝试的那一行算失败但不是拒绝；接手的那一次带 tries。
    @Test func rowTellsLegacyRejectionsAndHandedOnTries() throws {
        let json = #"""
            [{"t":"2026-11-08T08:21:57Z","status":404,"err":"unknown model"},
             {"t":"2026-11-08T08:21:58Z","provider":"deepseek","status":529,"handed_on":true},
             {"t":"2026-11-08T08:21:59Z","provider":"deepseek","status":200,"tries":2}]
            """#
        let rows = try MagpieJSON.decoder().decode([RequestRow].self, from: Data(json.utf8))
        #expect(!rows[0].rejected)
        #expect(rows[0].isRejected)
        #expect(rows[1].handedOn)
        #expect(rows[1].failed)
        #expect(!rows[1].isRejected)
        #expect(rows[2].tries == 2)
        #expect(!rows[2].failed)
        #expect(!rows[2].handedOn)
    }

    @Test func namedFallsBackToItsID() throws {
        let json = #"[{"id":"curl"},{"id":"codex","name":"Codex"},{"id":"x","name":""}]"#
        let named = try JSONDecoder().decode([Named].self, from: Data(json.utf8))
        #expect(named.map(\.name) == ["curl", "Codex", "x"])
    }

    /// 30 天的时间轴按天切成 30 个桶，只有最后一天有调用；by 里是整个时段的份额。
    @Test func requestLedgerSeriesAndShares() throws {
        let ledger = try MagpieJSON.decoder().decode(RequestLedger.self, from: fixture("requests"))
        #expect(ledger.bucket == .day)
        #expect(ledger.series.count == 30)
        #expect(ledger.series.first?.label == "Oct 10")
        #expect(ledger.series.first?.totals.calls == 0)
        #expect(ledger.series.first?.parts(by: .agent).isEmpty == true)

        let today = try #require(ledger.series.last)
        #expect(today.label == "Nov 8")
        #expect(today.totals.calls == 4)
        #expect(today.parts(by: .agent)["claude"]?.calls == 3)
        #expect(today.parts(by: .agent)["codex"]?.calls == 1)
        #expect(today.parts(by: .provider)["deepseek"] == SeriesPart(calls: 4))

        #expect(ledger.shares(by: .agent).map(\.name) == ["Claude Code", "Codex"])
        #expect(ledger.shares(by: .agent).first?.totals.calls == 3)
        #expect(ledger.shares(by: .provider).map(\.id) == ["deepseek"])
        // 模型没有单独的显示名，就用 id。
        #expect(ledger.shares(by: .model).first?.name == "deepseek-v4-flash")
    }

    @Test func requestRowFailureRules() throws {
        let json = """
            [{"t":"2026-11-08T08:00:00Z","status":200,"in":10,"out":5,"cache_read":3,"cache_write":1},
             {"t":"2026-11-08T08:00:00Z","status":499,"err":"canceled","canceled":true},
             {"t":"2026-11-08T08:00:00Z","status":0,"err":"timeout"},
             {"t":"2026-11-08T08:00:00Z","status":0}]
            """
        let rows = try MagpieJSON.decoder().decode([RequestRow].self, from: Data(json.utf8))
        #expect(!rows[0].failed)
        #expect(rows[0].tokens == 19)
        #expect(!rows[1].failed)
        #expect(rows[1].canceled)
        #expect(rows[2].failed)
        #expect(!rows[3].failed)
        #expect(rows[3].displayModel == "—")
    }

    @Test(arguments: [
        ("2026-11-08T08:24:22.990383053Z", "2026-11-08T08:24:22.990Z"),
        ("2026-11-08T08:24:22.7Z", "2026-11-08T08:24:22.700Z"),
        ("2026-11-08T16:24:22.5+08:00", "2026-11-08T08:24:22.500Z"),
        ("2026-11-09T00:00:00Z", "2026-11-09T00:00:00.000Z"),
    ])
    func rfc3339NanoParses(text: String, canonical: String) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = try #require(formatter.date(from: canonical))
        #expect(RFC3339.date(from: text) == expected)
    }

    @Test func rfc3339RejectsGarbageAndReadsGoZero() {
        #expect(RFC3339.date(from: "yesterday") == nil)
        let zero = RFC3339.date(from: "0001-01-01T00:00:00Z")
        #expect(zero != nil)
        #expect(zero.map { $0 < Date(timeIntervalSince1970: 0) } == true)
    }
}
