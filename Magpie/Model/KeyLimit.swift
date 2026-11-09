import Foundation

/// GET /v1/magpie/limit: what restricts the key.
nonisolated struct KeyLimit: Decodable, Hashable, Sendable {
    var limited: Bool
    var key: String
    /// Any of budget, models, and accounts; empty for a key with no restrictions.
    var heldTo: [String]
    /// The allowed models, which can be wildcards such as claude/*.
    var models: [String]
    var limits: [LimitStatus]
    /// The issuer's limits when this key was issued under another held key: all the keys that
    /// issuer issued count together.
    var issuerLimits: [LimitStatus]
    /// Whether a held key can see the account's quotas; if so, quotaProviders lists which
    /// providers the key can see.
    var quotas: Bool
    var quotaProviders: [String]
    /// The MCP servers (github) and tools (github/search_code) the key can use. Empty means all;
    /// just one "-" means none at all.
    var mcp: [String]
    var expires: Date?

    /// The entry the gateway uses to mean "no MCP server at all" (access.NoMCP).
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
