import Foundation
import Testing

@testable import Magpie

@Suite struct SnippetTests {
    private let base = URL(string: "https://magpie.example.com")!
    private let model = "deepseek/deepseek-v4-flash"

    @Test func claudeCodeSettingsAreValidJSONWithPlaceholderKey() throws {
        let blocks = SetupSnippet.blocks(for: .claudeCode, baseURL: base, key: nil, model: model)
        #expect(blocks.map(\.title) == ["~/.claude/settings.json"])
        let root = try JSONSerialization.jsonObject(with: Data(blocks[0].text.utf8))
        let env = try #require((root as? [String: Any])?["env"] as? [String: String])
        #expect(env["ANTHROPIC_BASE_URL"] == "https://magpie.example.com")
        #expect(env["ANTHROPIC_AUTH_TOKEN"] == "YOUR_GATEWAY_KEY")
        #expect(env["ANTHROPIC_MODEL"] == model)
        #expect(env["ANTHROPIC_DEFAULT_OPUS_MODEL"] == model)
        #expect(env["ANTHROPIC_DEFAULT_SONNET_MODEL"] == model)
        #expect(env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] == model)
        #expect(env.count == 6)
    }

    @Test func codexConfigUsesV1AndRealKeyWhenAsked() {
        let blocks = SetupSnippet.blocks(for: .codex, baseURL: base, key: "sk-x", model: model)
        #expect(blocks.map(\.title) == ["~/.codex/config.toml"])
        let lines = blocks[0].text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(
            lines == [
                "model = \"deepseek/deepseek-v4-flash\"",
                "model_provider = \"magpie\"",
                "",
                "[model_providers.magpie]",
                "name = \"magpie\"",
                "base_url = \"https://magpie.example.com/v1\"",
                "wire_api = \"responses\"",
                "experimental_bearer_token = \"sk-x\"",
            ])
    }

    @Test func openAICompatibleListsThreeValues() {
        let blocks = SetupSnippet.blocks(for: .openAI, baseURL: base, key: nil, model: nil)
        #expect(blocks.map(\.title) == ["Base URL", "API Key", "模型"])
        #expect(
            blocks.map(\.text) == ["https://magpie.example.com/v1", "YOUR_GATEWAY_KEY", "MODEL_ID"])
    }

    @Test func curlQuotesKeyAndBody() {
        let blocks = SetupSnippet.blocks(for: .curl, baseURL: base, key: "sk-it's", model: model)
        let text = blocks[0].text
        #expect(text.hasPrefix("curl https://magpie.example.com/v1/chat/completions \\\n"))
        #expect(text.contains("-H 'Authorization: Bearer sk-it'\\''s' \\\n"))
        #expect(
            text.contains(
                #"-d '{"model":"deepseek/deepseek-v4-flash","messages":[{"role":"user","content":"Say hi"}]}'"#
            ))
    }

    @Test func jsonLiteralEscapes() {
        #expect(SetupSnippet.json("a\"b\\c\nd") == #""a\"b\\c\nd""#)
        #expect(SetupSnippet.json("中文") == "\"中文\"")
    }

    @Test func formatsMoneyTokensAndDurations() {
        #expect(Format.usd(0.5) == "$0.50")
        #expect(Format.usd(99.999) == "$100.00")
        #expect(Format.usd(250) == "$250")
        #expect(Format.unitCost(2.5) == "$2.50")
        #expect(Format.unitCost(0.0589) == "$0.059")
        #expect(Format.unitCost(0.00123) == "$0.0012")
        #expect(Format.duration(ms: 267) == "267 ms")
        #expect(Format.duration(ms: 1500) == "1.5 s")
        #expect(Format.tokens(0) == "0")
    }
}
