/// GET /v1/magpie/me：一把网关密钥自己能看到的一切。
nonisolated struct KeyInfo: Decodable, Hashable, Sendable {
    var name: String
    /// 只能看用量、不能调用模型的密钥；此时 models 为空。
    var readOnly: Bool
    var limits: [LimitStatus]
    /// 按 UsagePeriod 的原始值（today、7d、30d）分组。
    var usage: [String: UsageTotals]
    /// 最近 30 天调用最多的模型，最多 8 个。
    var topModels: [TopModel]
    var models: [ModelEntry]
    var version: String

    func totals(for period: UsagePeriod) -> UsageTotals {
        usage[period.rawValue] ?? UsageTotals()
    }

    /// 配置页默认选中的模型：最常用且这把密钥仍可用的那个，否则列表的第一个。
    var suggestedModel: ModelEntry? {
        topModels.lazy.compactMap(entry(matching:)).first ?? models.first
    }

    /// models 里对应这个常用模型的那项。topModels 里是供应商自己的模型名，可能没有 provider/ 前缀。
    func entry(matching top: TopModel) -> ModelEntry? {
        models.first { $0.id == top.id || $0.id.hasSuffix("/" + top.id) }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
        limits = try container.decodeIfPresent([LimitStatus].self, forKey: .limits) ?? []
        usage = try container.decodeIfPresent([String: UsageTotals].self, forKey: .usage) ?? [:]
        topModels = try container.decodeIfPresent([TopModel].self, forKey: .topModels) ?? []
        models = try container.decodeIfPresent([ModelEntry].self, forKey: .models) ?? []
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
    }

    private enum CodingKeys: CodingKey {
        case name, readOnly, limits, usage, topModels, models, version
    }
}

/// topModels 的一项：模型 id 加上它的合计，网关把两者平铺在一个对象里。
nonisolated struct TopModel: Decodable, Hashable, Identifiable, Sendable {
    var id: String
    var totals: UsageTotals

    init(from decoder: any Decoder) throws {
        id = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .id)
        totals = try UsageTotals(from: decoder)
    }

    private enum CodingKeys: CodingKey {
        case id
    }
}

/// 密钥可以调用的模型：provider/model 形式的 id 和给人看的名字。
nonisolated struct ModelEntry: Decodable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String

    init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? id
    }

    private enum CodingKeys: CodingKey {
        case id, label
    }
}
