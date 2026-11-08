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
    var expires: Date?

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

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limited = try container.decodeIfPresent(Bool.self, forKey: .limited) ?? false
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        heldTo = try container.decodeIfPresent([String].self, forKey: .heldTo) ?? []
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? []
        limits = try container.decodeIfPresent([LimitStatus].self, forKey: .limits) ?? []
        expires = try container.decodeIfPresent(Date.self, forKey: .expires)
    }

    private enum CodingKeys: CodingKey {
        case limited, key, heldTo, models, limits, expires
    }
}
