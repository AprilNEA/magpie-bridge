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
        #expect(limit.expires == nil)
    }

    @Test func requestLedgerFromGateway() throws {
        let ledger = try MagpieJSON.decoder().decode(RequestLedger.self, from: fixture("requests"))
        #expect(ledger.total == 5)
        #expect(ledger.offset == 0)
        #expect(ledger.rows.count == 5)
        // 被网关直接拒绝的 404 不算一次调用，所以合计是 4。
        #expect(ledger.totals.calls == 4)
        #expect(ledger.totals.errors == 4)

        let rejected = ledger.rows[0]
        #expect(rejected.status == 404)
        #expect(rejected.error == "unknown model")
        #expect(rejected.agent == "curl")
        #expect(rejected.failed)
        #expect(!rejected.canceled)
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
