import Charts
import SwiftUI

/// This key's own call records, newest first, loading the next page automatically as you scroll.
/// Can show only failures, filter by model, Agent, or provider, or search text; the gateway does
/// the filtering, and the totals and the sparkline follow.
struct RequestsView: View {
    let session: Session

    @State private var period = UsagePeriod.week
    @State private var filter = RequestFilter()
    /// Text in the search field; it goes into filter.query to ask the gateway only after typing
    /// pauses for a moment.
    @State private var searchText = ""
    /// The first page: totals, series, shares, and the Agents and providers for filtering all live
    /// here; paging only appends rows.
    @State private var ledger: RequestLedger?
    @State private var rows: [RequestRow] = []
    @State private var loading = false
    @State private var failure: String?

    /// Period and filter together decide what to load; a change refetches the first page.
    private struct LoadKey: Hashable {
        var period: UsagePeriod
        var filter: RequestFilter
    }

    /// The overview tab passes a filter and period when a top model is tapped; the requests tab
    /// uses the defaults.
    init(session: Session, filter: RequestFilter = RequestFilter(), period: UsagePeriod = .week) {
        self.session = session
        _filter = State(initialValue: filter)
        _period = State(initialValue: period)
    }

    var body: some View {
        List {
            Section {
                Picker("时间范围", selection: $period) {
                    ForEach(UsagePeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if !filter.isEmpty {
                    FilterChips(filter: filter, ledger: ledger, remove: remove)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if let series = ledger?.series, series.contains(where: { $0.totals.calls > 0 }) {
                    CallsSparkline(series: series)
                        .accessibilityIdentifier("requests.trend")
                }
            } footer: {
                if let ledger, ledger.total > 0 {
                    Text(summary(of: ledger))
                        .accessibilityIdentifier("requests.summary")
                }
            }
            Section {
                ForEach(rows) { row in
                    NavigationLink(value: row) {
                        RequestRowView(row: row)
                    }
                }
                if let ledger, rows.count < ledger.total {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await loadMore() }
                }
            }
        }
        .searchable(text: $searchText, prompt: "模型、提供方、上游主机")
        .onSubmit(of: .search) { filter.query = searchText }
        .task(id: searchText) { await commitSearch() }
        .overlay {
            if rows.isEmpty {
                if loading {
                    ProgressView()
                } else if let failure {
                    ContentUnavailableView {
                        Label("没有拿到记录", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("重试") { Task { await reload() } }
                    }
                } else if !filter.isEmpty {
                    ContentUnavailableView {
                        Label("没有匹配的请求", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("\(period.title)没有符合这些条件的调用。")
                    } actions: {
                        Button("清除筛选") { clearFilter() }
                    }
                } else {
                    ContentUnavailableView(
                        "没有请求", systemImage: "tray",
                        description: Text("\(period.title)这把密钥没有调用。"))
                }
            }
        }
        .navigationTitle("请求")
        .toolbar { filterMenu }
        .navigationDestination(for: RequestRow.self) { row in
            RequestDetailView(row: row)
        }
        .task(id: LoadKey(period: period, filter: filter)) { await reload() }
        .refreshable { await reload() }
    }

    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle("只看失败", isOn: $filter.failed)
                Picker("模型", selection: $filter.model) {
                    Text("全部模型").tag("")
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                Picker("Agent", selection: $filter.agent) {
                    Text("全部 Agent").tag("")
                    ForEach(agentOptions) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                .pickerStyle(.menu)
                Picker("提供方", selection: $filter.provider) {
                    Text("全部提供方").tag("")
                    ForEach(providerOptions) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                if !filter.isEmpty {
                    Divider()
                    Button("清除筛选", role: .destructive) { clearFilter() }
                }
            } label: {
                Label(
                    "筛选",
                    systemImage: filter.isEmpty
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
            }
            .accessibilityIdentifier("requests.filter")
        }
    }

    /// Models in the dropdown: the ones used in this period. The gateway computes by.model without
    /// the model filter, so after picking one the others stay. When the period just changed and
    /// the selected model is not in the list, keep it as well, so the menu still shows a checkmark.
    private var modelOptions: [String] {
        var ids = (ledger?.shares(by: .model) ?? []).map(\.id).filter { !$0.isEmpty }
        if !filter.model.isEmpty, !ids.contains(filter.model) {
            ids.append(filter.model)
        }
        return ids
    }

    private var agentOptions: [Named] {
        Self.options(ledger?.agents ?? [], keeping: filter.agent)
    }

    private var providerOptions: [Named] {
        Self.options(ledger?.providers ?? [], keeping: filter.provider)
    }

    private static func options(_ named: [Named], keeping picked: String) -> [Named] {
        guard !picked.isEmpty, !named.contains(where: { $0.id == picked }) else { return named }
        return named + [Named(id: picked, name: picked)]
    }

    private func summary(of ledger: RequestLedger) -> String {
        var parts = [
            "\(Format.count(ledger.totals.calls)) 次请求",
            "\(Format.tokens(ledger.totals.tokens)) tokens",
        ]
        if ledger.totals.errors > 0 {
            parts.append("\(Format.count(ledger.totals.errors)) 次失败")
        }
        if ledger.totals.cost > 0 {
            parts.append("约 \(Format.usd(ledger.totals.cost))")
        }
        return (filter.isEmpty ? "" : "筛选后：") + parts.joined(separator: " · ")
    }

    private func remove(_ field: RequestFilter.Field) {
        filter.clear(field)
        if field == .query {
            searchText = ""
        }
    }

    private func clearFilter() {
        filter = RequestFilter()
        searchText = ""
    }

    /// Asks the gateway 350 ms after typing stops, so not every keystroke sends a request;
    /// pressing return skips the wait.
    private func commitSearch() async {
        guard searchText != filter.query else { return }
        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            return
        }
        filter.query = searchText
    }

    private func reload() async {
        guard let client = session.client else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await client.requests(period: period, filter: filter)
            ledger = page
            rows = page.rows
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let client = session.client, let ledger, !loading, rows.count < ledger.total else {
            return
        }
        loading = true
        defer { loading = false }
        do {
            let page = try await client.requests(
                period: period, filter: filter, offset: rows.count)
            rows += page.rows
            self.ledger?.total = page.total
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// The active filters, one capsule each; tapping one removes it.
private struct FilterChips: View {
    let filter: RequestFilter
    let ledger: RequestLedger?
    let remove: (RequestFilter.Field) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(filter.activeFields, id: \.self) { field in
                    Button {
                        withAnimation(.snappy) { remove(field) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(title(of: field))
                                .lineLimit(1)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .accessibilityIdentifier("requests.chip.\(field.rawValue)")
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    /// Agents and providers show by name, falling back to the id only when the ledger lacks them.
    private func title(of field: RequestFilter.Field) -> String {
        switch field {
        case .failed: "只看失败"
        case .model: filter.model
        case .agent:
            ledger?.agents.first(where: { $0.id == filter.agent })?.name ?? filter.agent
        case .provider:
            ledger?.providers.first(where: { $0.id == filter.provider })?.name ?? filter.provider
        case .query: "“\(filter.query.trimmingCharacters(in: .whitespacesAndNewlines))”"
        }
    }
}

/// The sparkline above the list: how many calls succeeded and failed in each bucket.
private struct CallsSparkline: View {
    let series: [SeriesPoint]

    var body: some View {
        let hasErrors = series.contains { $0.totals.errors > 0 }
        Chart(series) { point in
            AreaMark(
                x: .value("时间", point.label),
                y: .value("请求", point.totals.calls),
                series: .value("类别", "请求")
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
            LineMark(
                x: .value("时间", point.label),
                y: .value("请求", point.totals.calls),
                series: .value("类别", "请求")
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if hasErrors {
                LineMark(
                    x: .value("时间", point.label),
                    y: .value("失败", point.totals.errors),
                    series: .value("类别", "失败")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            if point.id == series.last?.id {
                PointMark(x: .value("时间", point.label), y: .value("请求", point.totals.calls))
                    .symbolSize(60)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .chartXScale(domain: series.map(\.label))
        .chartXAxis {
            let shown = Set(ChartData.axisLabels(series.map(\.label)))
            AxisMarks { value in
                if let label = value.as(String.self), shown.contains(label) {
                    AxisValueLabel { Text(label) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 110)
        .padding(.vertical, 6)
    }
}

struct RequestRowView: View {
    let row: RequestRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.displayModel)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("requests.row.model")
                Spacer()
                if let outcome {
                    Text(outcome.text)
                        .font(outcome.alarming ? .caption.weight(.medium) : .caption)
                        .foregroundStyle(outcome.alarming ? .red : .secondary)
                }
            }
            HStack(spacing: 4) {
                Text(row.agentName.isEmpty ? row.agent : row.agentName)
                if !row.providerName.isEmpty {
                    Text("·")
                    Text(row.providerName)
                }
                Spacer()
                Text(Format.when(row.time))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TokenStat(value: row.input, icon: "arrow.up")
                TokenStat(value: row.output, icon: "arrow.down")
                if row.cacheRead > 0 {
                    TokenStat(value: row.cacheRead, icon: "bolt")
                }
                Spacer()
                if row.priced {
                    Text("约 \(Format.usd(row.cost))")
                }
                Text(Format.duration(ms: row.millis))
            }
            .lineLimit(1)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    /// The badge in the top-right corner; successes get none. The Agent never saw the error of a
    /// failed call that the gateway retried, so that one is not marked red.
    private var outcome: (text: String, alarming: Bool)? {
        let code = row.status > 0 ? " \(row.status)" : ""
        if row.handedOn {
            return ("已重试", false)
        }
        if row.canceled {
            return ("已取消", false)
        }
        if row.isRejected {
            return ("拒绝" + code, true)
        }
        if row.failed {
            return ("失败" + code, true)
        }
        return nil
    }
}

/// One token count in a row: an arrow plus a number. Not a Label, which inside this row's HStack
/// would squeeze the digits into a vertical column.
private struct TokenStat: View {
    let value: Int
    let icon: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            Text(Format.tokens(value))
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

struct RequestDetailView: View {
    let row: RequestRow

    var body: some View {
        Form {
            Section {
                LabeledContent("时间", value: row.time.formatted(date: .abbreviated, time: .standard))
                LabeledContent("模型", value: row.displayModel)
                if let requested = row.requested, requested != row.model {
                    LabeledContent("请求的模型", value: requested)
                }
                if let served = row.served, served != row.model {
                    LabeledContent("实际模型", value: served)
                }
                LabeledContent("Agent", value: row.agentName.isEmpty ? row.agent : row.agentName)
                if !row.providerName.isEmpty {
                    LabeledContent("提供方", value: row.providerName)
                }
                if let endpoint = row.endpoint {
                    LabeledContent("端点", value: endpoint)
                }
            }
            Section {
                LabeledContent("状态", value: status)
                if let errorType = row.errorType, !errorType.isEmpty {
                    LabeledContent("错误类型", value: errorType)
                }
                if let error = row.error, !error.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if row.tries > 1 {
                    LabeledContent("尝试次数", value: Format.count(row.tries))
                }
                LabeledContent("用时", value: Format.duration(ms: row.millis))
            } header: {
                Text("结果")
            } footer: {
                if row.isRejected {
                    Text("网关自己拒绝了这次请求，没有发给任何提供方，不算一次调用。")
                } else if row.handedOn {
                    Text("这次尝试失败后网关换了一次重试，Agent 没有收到这个错误，不算一次调用。")
                }
            }
            if hasUpstream {
                Section("上游") {
                    if let host = row.host, !host.isEmpty {
                        LabeledContent("主机", value: host)
                    }
                    if row.upBytes > 0 || row.downBytes > 0 {
                        LabeledContent("发出", value: Format.bytes(row.upBytes))
                        LabeledContent("收到", value: Format.bytes(row.downBytes))
                    }
                }
            }
            Section("Tokens") {
                LabeledContent("输入", value: Format.count(row.input))
                LabeledContent("输出", value: Format.count(row.output))
                LabeledContent("缓存读取", value: Format.count(row.cacheRead))
                LabeledContent("缓存写入", value: Format.count(row.cacheWrite))
                if row.reasoning > 0 {
                    LabeledContent("推理", value: Format.count(row.reasoning))
                }
                LabeledContent("费用", value: row.priced ? "约 \(Format.usd(row.cost))" : "未定价")
            }
        }
        .navigationTitle("请求详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Only calls that actually reached a provider have these: the host and the bytes each way.
    private var hasUpstream: Bool {
        !(row.host ?? "").isEmpty || row.upBytes > 0 || row.downBytes > 0
    }

    private var status: String {
        let code = row.status > 0 ? " \(row.status)" : ""
        if row.canceled {
            return "Agent 取消"
        }
        if row.isRejected {
            return "网关拒绝" + code
        }
        if row.failed {
            return "失败" + code
        }
        return "成功" + code
    }
}
