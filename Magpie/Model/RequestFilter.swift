import Foundation

/// The request page's filter: the few fields of usage.Filter that apply when a key views its own
/// calls. The gateway filters on the server, so the list, totals, series, and shares are all
/// filtered.
nonisolated struct RequestFilter: Hashable, Sendable {
    /// Only requests where the Agent received an error (failed=1); requests the Agent itself
    /// canceled do not count.
    var failed = false
    /// The provider's model id, the same as RequestRow.model; an empty string does not filter.
    var model = ""
    var agent = ""
    var provider = ""
    /// Text to find in the requested model, provider, upstream host, session, and key name (q).
    var query = ""

    enum Field: String, CaseIterable, Hashable, Sendable {
        case failed, model, agent, provider, query
    }

    var isEmpty: Bool { activeFields.isEmpty }

    /// The conditions that are set, in Field order.
    var activeFields: [Field] {
        Field.allCases.filter { field in
            switch field {
            case .failed: failed
            case .model: !model.isEmpty
            case .agent: !agent.isEmpty
            case .provider: !provider.isEmpty
            case .query: !trimmedQuery.isEmpty
            }
        }
    }

    mutating func clear(_ field: Field) {
        switch field {
        case .failed: failed = false
        case .model: model = ""
        case .agent: agent = ""
        case .provider: provider = ""
        case .query: query = ""
        }
    }

    /// The query parameters added to /v1/magpie/usage/requests; unset conditions are left out.
    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if failed {
            items.append(URLQueryItem(name: "failed", value: "1"))
        }
        let named = [
            ("model", model), ("agent", agent), ("provider", provider), ("q", trimmedQuery),
        ]
        for (name, value) in named where !value.isEmpty {
            items.append(URLQueryItem(name: name, value: value))
        }
        return items
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
