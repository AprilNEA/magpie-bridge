import Foundation

/// 请求页的筛选条件：usage.Filter 里一把密钥看自己的调用时用得上的几项。
/// 网关在服务器上筛，所以列表、合计、时间轴和份额都是筛过的。
nonisolated struct RequestFilter: Hashable, Sendable {
    /// 只看 Agent 收到了错误的请求（failed=1）；Agent 自己取消的不算。
    var failed = false
    /// 供应商的模型 id，和 RequestRow.model 一样；空字符串不筛。
    var model = ""
    var agent = ""
    var provider = ""
    /// 在请求的模型、提供方、上游主机、会话和密钥名里找的文本（q）。
    var query = ""

    enum Field: String, CaseIterable, Hashable, Sendable {
        case failed, model, agent, provider, query
    }

    var isEmpty: Bool { activeFields.isEmpty }

    /// 设了的条件，按 Field 的顺序。
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

    /// 加到 /v1/magpie/usage/requests 上的查询参数；没设的条件不带。
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
