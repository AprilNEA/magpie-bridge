/// The time window the gateway tallies usage over (usage.Period).
nonisolated enum UsagePeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case week = "7d"
    case month = "30d"
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今天"
        case .week: "7 天"
        case .month: "30 天"
        case .all: "全部"
        }
    }
}
