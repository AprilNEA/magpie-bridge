import Foundation

/// 配置页的目标工具，和网页 /me 的四个标签一致。
nonisolated enum SetupTarget: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case openAI
    case curl

    var id: String { rawValue }

    /// 分段控件四格并排，iPhone 上每格只放得下六七个字母，所以用短名字。
    var title: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        case .openAI: "OpenAI"
        case .curl: "测试"
        }
    }

    var note: String {
        switch self {
        case .claudeCode: "加到 ~/.claude/settings.json 里，然后启动 claude。模型为上面选中的那个。"
        case .codex: "加到 ~/.codex/config.toml 里，然后启动 codex。模型为上面选中的那个。"
        case .openAI: "适用于任何支持 OpenAI 兼容接口的应用或 SDK。"
        case .curl: "在终端里运行，检查密钥能否使用。"
        }
    }
}

/// 生成和网页 /me 一样的配置片段。
nonisolated enum SetupSnippet {
    static let keyPlaceholder = "YOUR_GATEWAY_KEY"
    static let modelPlaceholder = "MODEL_ID"

    struct Block: Hashable, Identifiable, Sendable {
        /// 写到哪个文件，或者这一项叫什么。
        var title: String
        var text: String

        var id: String { title }
    }

    /// key 为 nil 时用占位符，这样片段可以放心分享。
    static func blocks(for target: SetupTarget, baseURL: URL, key: String?, model: String?)
        -> [Block]
    {
        let base = baseURL.absoluteString
        let v1 = base + "/v1"
        let key = key ?? keyPlaceholder
        let model = model ?? modelPlaceholder
        switch target {
        case .claudeCode:
            let env = [
                ("ANTHROPIC_BASE_URL", base),
                ("ANTHROPIC_AUTH_TOKEN", key),
                ("ANTHROPIC_MODEL", model),
                ("ANTHROPIC_DEFAULT_OPUS_MODEL", model),
                ("ANTHROPIC_DEFAULT_SONNET_MODEL", model),
                ("ANTHROPIC_DEFAULT_HAIKU_MODEL", model),
            ]
            let lines = env.map { "    \(json($0.0)): \(json($0.1))" }.joined(separator: ",\n")
            return [
                Block(title: "~/.claude/settings.json", text: "{\n  \"env\": {\n\(lines)\n  }\n}")
            ]
        case .codex:
            let lines = [
                "model = \(json(model))",
                "model_provider = \"magpie\"",
                "",
                "[model_providers.magpie]",
                "name = \"magpie\"",
                "base_url = \(json(v1))",
                "wire_api = \"responses\"",
                "experimental_bearer_token = \(json(key))",
            ]
            return [Block(title: "~/.codex/config.toml", text: lines.joined(separator: "\n"))]
        case .openAI:
            return [
                Block(title: "Base URL", text: v1),
                Block(title: "API Key", text: key),
                Block(title: "模型", text: model),
            ]
        case .curl:
            let body =
                "{\"model\":\(json(model)),\"messages\":[{\"role\":\"user\",\"content\":\"Say hi\"}]}"
            let command = [
                "curl \(v1)/chat/completions \\",
                "  -H \(shell("Authorization: Bearer \(key)")) \\",
                "  -H 'Content-Type: application/json' \\",
                "  -d \(shell(body))",
            ]
            return [Block(title: "curl", text: command.joined(separator: "\n"))]
        }
    }

    /// JSON 字符串字面量，和 JSON.stringify 一样。
    static func json(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20:
                out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// 单引号包起来的 shell 参数。
    static func shell(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
