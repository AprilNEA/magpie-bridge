import SwiftUI

/// The top half of the web /me page plus charts: limit gauges, usage numbers, a year of days as a
/// heatmap, the trend over time, and the breakdown by model, Agent, or provider.
struct OverviewView: View {
    let session: Session

    @State private var period = UsagePeriod.week
    /// What every chart on the page measures.
    @State private var metric = UsageMetric.tokens
    @State private var style = TrendChart.Style.bars
    @State private var dimension = Dimension.model
    /// The period tapped in usage; its token breakdown expands below. Unrelated to the trend
    /// chart's period.
    @State private var usagePeriod = UsagePeriod.today
    /// Data for the charts: this period's ledger (only the first page; every page carries the trend
    /// and shares).
    @State private var ledger: RequestLedger?
    @State private var ledgerError: String?
    /// Data for the heatmap: fetched when the page first appears and on every refresh, not when
    /// the period changes.
    @State private var heatmap: Heatmap?
    @State private var heatmapError: String?

    var body: some View {
        List {
            if let info = session.info {
                if let error = session.refreshError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                limits(info)
                usage(info)
                year
                trend
                breakdown
                topModels(info)
                if info.readOnly {
                    Section {
                        Text("这个密钥只能查看用量，不能调用模型。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if session.info == nil {
                if session.isRefreshing {
                    ProgressView()
                } else {
                    ContentUnavailableView {
                        Label("没有拿到数据", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(session.refreshError ?? "")
                    } actions: {
                        Button("重试") { Task { await refresh() } }
                    }
                }
            }
        }
        .navigationTitle(session.info?.name ?? "概览")
        .navigationDestination(for: TopModel.self) { model in
            RequestsView(session: session, filter: RequestFilter(model: model.id), period: .month)
        }
        .task(id: period) { await loadLedger() }
        .task {
            if heatmap == nil {
                await loadHeatmap()
            }
        }
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                .disabled(session.isRefreshing)
            }
        }
    }

    private func limits(_ info: KeyInfo) -> some View {
        Section("额度") {
            if info.limits.isEmpty {
                Text("这个密钥没有额度限制。").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(info.limits) { limit in
                        LimitGauge(limit: limit)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func usage(_ info: KeyInfo) -> some View {
        Section {
            HStack(alignment: .top, spacing: 4) {
                ForEach([UsagePeriod.today, .week, .month]) { period in
                    UsageCell(
                        period: period, totals: info.totals(for: period),
                        selected: period == usagePeriod
                    ) {
                        withAnimation(.snappy) { usagePeriod = period }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
            UsageDetail(period: usagePeriod, totals: info.totals(for: usagePeriod))
        } header: {
            Text("用量")
        } footer: {
            Text("缓存命中是提示词 tokens 里从缓存读出来的比例；平均每次按全部调用算。")
        }
    }

    /// The web dashboard's heatmap: the last 53 weeks a day each, whatever period is chosen below.
    private var year: some View {
        Section {
            chartBody(heatmap, error: heatmapError, identifier: "overview.year") { heatmap in
                if heatmap.hasCalls {
                    HeatmapChart(heatmap: heatmap, metric: metric)
                } else {
                    Text("过去一年还没有调用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        } header: {
            HStack {
                Text("过去一年")
                Spacer()
                metricPicker(identifier: "overview.heatmap.metric")
            }
        } footer: {
            Text("一格是一天，颜色越深用得越多；一天从网关所在时区的零点算起。")
        }
    }

    private var trend: some View {
        Section {
            Picker("时间范围", selection: $period) {
                ForEach(UsagePeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            chartBody(ledger, error: ledgerError, identifier: "overview.trend") { ledger in
                TrendChart(ledger: ledger, dimension: dimension, metric: metric, style: style)
            }
        } header: {
            HStack {
                Text("趋势")
                Spacer()
                Picker("图形", selection: $style) {
                    ForEach(TrendChart.Style.allCases) { style in
                        Image(systemName: style.symbol)
                            .accessibilityLabel(style.title)
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("overview.style")
                metricPicker(identifier: "overview.metric")
            }
        } footer: {
            if let ledger {
                Text(summary(of: ledger))
                    .accessibilityIdentifier("overview.summary")
            }
        }
    }

    private var breakdown: some View {
        Section("构成") {
            Picker("维度", selection: $dimension) {
                ForEach(Dimension.allCases) { dimension in
                    Text(dimension.title).tag(dimension)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            chartBody(ledger, error: ledgerError, identifier: "overview.share") { ledger in
                let slices = ChartData.slices(in: ledger, by: dimension, metric: metric)
                let names = slices.map(\.name)
                if slices.isEmpty {
                    Text("这段时间没有\(metric.title.lowercased())。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ShareChart(slices: slices, names: names, dimension: dimension, metric: metric)
                        .padding(.vertical, 4)
                }
            }
            if let ledger {
                let slices = ChartData.slices(in: ledger, by: dimension, metric: metric)
                let names = slices.map(\.name)
                ForEach(slices) { slice in
                    ShareRow(
                        slice: slice, color: ChartData.color(of: slice.name, in: names),
                        metric: metric)
                }
            }
        }
    }

    /// The web /me page's "Top models in the last 30 days": the models /me already sorts by call
    /// count, at most 8, unrelated to the period above. Tapping one opens the 30-day request list
    /// filtered to that model.
    private func topModels(_ info: KeyInfo) -> some View {
        Section {
            if info.topModels.isEmpty {
                Text("还没有用量。").foregroundStyle(.secondary)
            } else {
                let most = max(info.topModels.map(\.totals.calls).max() ?? 0, 1)
                ForEach(info.topModels) { model in
                    NavigationLink(value: model) {
                        TopModelRow(
                            model: model, label: info.entry(matching: model)?.label,
                            share: Double(model.totals.calls) / Double(most))
                    }
                }
            }
        } header: {
            Text("最近 30 天最常用")
        } footer: {
            if !info.topModels.isEmpty {
                Text("按最近 30 天的调用次数排序，和上面选的时段无关；点一个看它的请求。")
            }
        }
    }

    /// The menu choosing what the charts measure. The trend and the heatmap each carry one in
    /// their header, both setting the same metric.
    private func metricPicker(identifier: String) -> some View {
        Picker("指标", selection: $metric) {
            ForEach(UsageMetric.allCases) { metric in
                Text(metric.title).tag(metric)
            }
        }
        .pickerStyle(.menu)
        .textCase(nil)
        .font(.footnote)
        .accessibilityIdentifier(identifier)
    }

    /// The row holding a chart: draws it once its data is here, otherwise the error that kept the
    /// data away, or a spinner while neither has arrived.
    private func chartBody<Value, Content: View>(
        _ value: Value?, error: String?, identifier: String,
        @ViewBuilder content: (Value) -> Content
    ) -> some View {
        VStack(alignment: .leading) {
            if let value {
                content(value)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
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
        return "\(period.title)：" + parts.joined(separator: " · ")
    }

    private func refresh() async {
        await session.refresh()
        async let ledgerLoaded: Void = loadLedger()
        await loadHeatmap()
        await ledgerLoaded
    }

    private func loadLedger() async {
        guard let client = session.client else { return }
        ledgerError = nil
        do {
            ledger = try await client.requests(period: period, limit: 1)
        } catch {
            ledgerError = error.localizedDescription
        }
    }

    private func loadHeatmap() async {
        guard let client = session.client else { return }
        heatmapError = nil
        do {
            heatmap = try await client.heatmap()
        } catch {
            heatmapError = error.localizedDescription
        }
    }
}

/// One row of the top models: the name takes a whole line (falling back to the id when the key's
/// model list lacks it) so the name and tokens never squeeze each other; the second line holds the
/// id and tokens, the third the calls, failures, and cost, then a bar with the call count relative
/// to the most-used model.
private struct TopModelRow: View {
    let model: TopModel
    /// The human-readable name from the model list; nil for a read-only key, which has no list.
    let label: String?
    /// Call count relative to the most-used model, from 0 to 1.
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            } else {
                Text(model.id)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(alignment: .firstTextBaseline) {
                if label != nil {
                    Text(model.id)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text("\(Format.tokens(model.totals.tokens)) tokens")
                    .fixedSize()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            ProgressView(value: share)
                .tint(.accentColor)
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overview.top")
    }

    private var detail: String {
        var parts = ["\(Format.count(model.totals.calls)) 次"]
        if model.totals.errors > 0 {
            parts.append("\(Format.count(model.totals.errors)) 次失败")
        }
        if model.totals.cost > 0 {
            parts.append("约 \(Format.usd(model.totals.cost))")
        }
        return parts.joined(separator: " · ")
    }
}

/// One period's tokens, calls, and cost; tapping selects it and expands its breakdown below.
private struct UsageCell: View {
    let period: UsagePeriod
    let totals: UsageTotals
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 2) {
                Text(period.title)
                    .font(.caption)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(Format.tokens(totals.tokens))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("tokens · \(Format.count(totals.calls)) 次")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if totals.cost > 0 {
                    Text("约 \(Format.usd(totals.cost))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                selected ? Color.accentColor.opacity(0.1) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("overview.usage.\(period.rawValue)")
    }
}

/// Breakdown of the tapped period: a horizontal bar of the four token kinds, plus cache hits,
/// failure rate, and average cost per call.
private struct UsageDetail: View {
    let period: UsagePeriod
    let totals: UsageTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if totals.calls == 0 {
                Text("\(period.title)还没有调用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if totals.tokens > 0 {
                    TokenMixChart(totals: totals)
                }
                HStack(alignment: .top, spacing: 12) {
                    if let rate = totals.cacheHitRate {
                        Stat(title: "缓存命中", value: Self.percent(rate))
                    }
                    if let rate = totals.errorRate {
                        Stat(title: "失败率", value: Self.percent(rate))
                    }
                    if let cost = totals.averageCost, cost > 0 {
                        Stat(title: "平均每次", value: Format.unitCost(cost))
                    }
                }
                if totals.unpriced > 0 {
                    Text("\(Format.count(totals.unpriced)) 次调用的模型没有价格，费用里不含它们。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.usage.detail")
    }

    private static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0...1)))
    }
}

/// One small figure below the breakdown: title on top, value beneath.
private struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
