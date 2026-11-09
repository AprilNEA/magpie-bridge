import SwiftUI

/// 网页 /me 的上半部分加上图表：额度圆环、用量数字、按时间的趋势、按模型 / Agent / 提供方的构成。
struct OverviewView: View {
    let session: Session

    @State private var period = UsagePeriod.week
    @State private var metric = UsageMetric.tokens
    @State private var style = TrendChart.Style.bars
    @State private var dimension = Dimension.model
    /// 用量里点中的时段，下面展开它的 token 构成；和趋势图的时段无关。
    @State private var usagePeriod = UsagePeriod.today
    /// 图表的数据：这个时段的账本（只要第一页，趋势和份额每页都带）。
    @State private var ledger: RequestLedger?
    @State private var ledgerError: String?
    @State private var loadingLedger = false

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
            chartBody(identifier: "overview.trend") { ledger in
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
                Picker("指标", selection: $metric) {
                    ForEach(UsageMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.menu)
                .textCase(nil)
                .font(.footnote)
                .accessibilityIdentifier("overview.metric")
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
            chartBody(identifier: "overview.share") { ledger in
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

    /// 网页 /me 的「最近 30 天最常用」：/me 里按调用次数排好的模型，最多 8 个，和上面的时段无关。
    /// 点一个进到按它筛过的 30 天请求列表。
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

    /// 图表所在的那一行：有数据画图，没拿到数据转圈或报错。
    @ViewBuilder
    private func chartBody<Content: View>(
        identifier: String, @ViewBuilder content: (RequestLedger) -> Content
    ) -> some View {
        VStack(alignment: .leading) {
            if let ledger {
                content(ledger)
            } else if loadingLedger {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let ledgerError {
                Label(ledgerError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
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
        await loadLedger()
    }

    private func loadLedger() async {
        guard let client = session.client else { return }
        loadingLedger = true
        defer { loadingLedger = false }
        do {
            ledger = try await client.requests(period: period, limit: 1)
            ledgerError = nil
        } catch {
            ledgerError = error.localizedDescription
        }
    }
}

/// 常用模型的一行：名字占一整行（密钥的模型列表里没有就写 id），名字和 tokens 才不会互相挤；
/// 第二行是 id 和 tokens，第三行是次数、失败数和费用，再一条相对最常用那个的调用次数比例条。
private struct TopModelRow: View {
    let model: TopModel
    /// 模型列表里给人看的名字；只读密钥没有列表，为 nil。
    let label: String?
    /// 调用次数相对最常用那个的比例，0 到 1。
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

/// 一个时段的 tokens、次数和费用；点一下选中，下面展开它的构成。
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

/// 点中的时段的构成：四类 token 的横条，再加缓存命中、失败率和平均每次的费用。
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

/// 构成下面的一个小数字：标题在上，值在下。
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
