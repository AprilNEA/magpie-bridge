import SwiftUI

/// 网页 /me 的上半部分加上图表：额度圆环、用量数字、按时间的趋势、按模型 / Agent / 提供方的构成。
struct OverviewView: View {
    let session: Session

    @State private var period = UsagePeriod.week
    @State private var metric = UsageMetric.tokens
    @State private var style = TrendChart.Style.bars
    @State private var dimension = Dimension.model
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
        Section("用量") {
            HStack(alignment: .top, spacing: 12) {
                ForEach([UsagePeriod.today, .week, .month]) { period in
                    UsageCell(title: period.title, totals: info.totals(for: period))
                }
            }
            .padding(.vertical, 4)
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

private struct UsageCell: View {
    let title: String
    let totals: UsageTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Format.tokens(totals.tokens))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
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
    }
}
