import Foundation

/// GET /v1/magpie/limit：密钥受什么限制。
nonisolated struct KeyLimit: Decodable, Hashable, Sendable {
    var limited: Bool
    var key: String
    /// budget、models、accounts 中的若干个；没有限制的密钥为空。
    var heldTo: [String]
    /// 允许的模型，可以是 claude/* 这样的通配。
    var models: [String]
    var limits: [LimitStatus]
    /// 这把密钥是在另一把受限的密钥下签发的时候，签发者的额度：所有签发出去的密钥一起算。
    var issuerLimits: [LimitStatus]
    /// 受限的密钥能不能看到账号的配额；能的话 quotaProviders 是能看到哪些提供方的。
    var quotas: Bool
    var quotaProviders: [String]
    /// 能用的 MCP 服务器（github）和工具（github/search_code）。空是全部；只有一个 "-" 是一个都不能用。
    var mcp: [String]
    var expires: Date?

    /// 网关用来表示「一个 MCP 服务器都不能用」的那一项（access.NoMCP）。
    static let noMCP = "-"

    var heldToTitles: [String] {
        heldTo.map { held in
            switch held {
            case "budget": "额度"
            case "models": "模型"
            case "accounts": "账号"
            default: held
            }
        }
    }

    enum MCPAccess: Hashable, Sendable {
        case every
        case none
        case some([String])
    }

    var mcpAccess: MCPAccess {
        if mcp.isEmpty {
            return .every
        }
        if mcp == [Self.noMCP] {
            return .none
        }
        return .some(mcp.filter { $0 != Self.noMCP })
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limited = try container.decodeIfPresent(Bool.self, forKey: .limited) ?? false
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        heldTo = try container.decodeIfPresent([String].self, forKey: .heldTo) ?? []
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? []
        limits = try container.decodeIfPresent([LimitStatus].self, forKey: .limits) ?? []
        issuerLimits =
            try container.decodeIfPresent([LimitStatus].self, forKey: .issuerLimits) ?? []
        quotas = try container.decodeIfPresent(Bool.self, forKey: .quotas) ?? false
        quotaProviders =
            try container.decodeIfPresent([String].self, forKey: .quotaProviders) ?? []
        mcp = try container.decodeIfPresent([String].self, forKey: .mcp) ?? []
        expires = try container.decodeIfPresent(Date.self, forKey: .expires)
    }

    private enum CodingKeys: CodingKey {
        case limited, key, heldTo, models, limits, issuerLimits, quotas, quotaProviders, mcp
        case expires
    }
}
