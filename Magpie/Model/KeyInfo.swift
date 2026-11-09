/// GET /v1/magpie/me: everything a gateway key can see about itself.
nonisolated struct KeyInfo: Decodable, Hashable, Sendable {
    var name: String
    /// A key that can only view usage and cannot call models; models is empty then.
    var readOnly: Bool
    var limits: [LimitStatus]
    /// Grouped by the raw value of UsagePeriod (today, 7d, 30d).
    var usage: [String: UsageTotals]
    /// The most-called models over the last 30 days, at most 8.
    var topModels: [TopModel]
    var models: [ModelEntry]
    var version: String

    func totals(for period: UsagePeriod) -> UsageTotals {
        usage[period.rawValue] ?? UsageTotals()
    }

    /// The model the setup page selects by default: the top model this key can still use,
    /// otherwise the first one in the list.
    var suggestedModel: ModelEntry? {
        topModels.lazy.compactMap(entry(matching:)).first ?? models.first
    }

    /// The models entry for this top model. topModels holds the providers' own model names, which
    /// may lack the provider/ prefix.
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

/// One topModels item: the model id plus its totals; the gateway flattens both into one object.
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

/// A model the key can call: an id in provider/model form and a display name.
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
