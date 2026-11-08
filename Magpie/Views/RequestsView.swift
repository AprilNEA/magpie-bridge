import Charts
import SwiftUI

/// 这把密钥自己的调用记录，最新的在前，往下翻自动加载下一页。
struct RequestsView: View {
    let session: Session

    @State private var period = UsagePeriod.week
    @State private var rows: [RequestRow] = []
    @State private var total = 0
    @State private var totals = UsageTotals()
    @State private var series: [SeriesPoint] = []
    @State private var loading = false
    @State private var failure: String?

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
                if series.contains(where: { $0.totals.calls > 0 }) {
                    CallsSparkline(series: series)
                        .accessibilityIdentifier("requests.trend")
                }
            } footer: {
                if total > 0 {
                    Text(summary)
                        .accessibilityIdentifier("requests.summary")
                }
            }
            Section {
                ForEach(rows) { row in
                    NavigationLink(value: row) {
                        RequestRowView(row: row)
                    }
                }
                if rows.count < total {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await loadMore() }
                }
            }
        }
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
                } else {
                    ContentUnavailableView(
                        "没有请求", systemImage: "tray",
                        description: Text("\(period.title)这把密钥没有调用。"))
                }
            }
        }
        .navigationTitle("请求")
        .navigationDestination(for: RequestRow.self) { row in
            RequestDetailView(row: row)
        }
        .task(id: period) { await reload() }
        .refreshable { await reload() }
    }

    private var summary: String {
        var parts = ["\(Format.count(total)) 次请求", "\(Format.tokens(totals.tokens)) tokens"]
        if totals.errors > 0 {
            parts.append("\(Format.count(totals.errors)) 次失败")
        }
        if totals.cost > 0 {
            parts.append("约 \(Format.usd(totals.cost))")
        }
        return parts.joined(separator: " · ")
    }

    private func reload() async {
        guard let client = session.client else { return }
        loading = true
        defer { loading = false }
        do {
            let ledger = try await client.requests(period: period)
            rows = ledger.rows
            total = ledger.total
            totals = ledger.totals
            series = ledger.series
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let client = session.client, !loading, rows.count < total else { return }
        loading = true
        defer { loading = false }
        do {
            let ledger = try await client.requests(period: period, offset: rows.count)
            rows += ledger.rows
            total = ledger.total
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// 列表顶上的小图：每个桶成功和失败各多少次。
private struct CallsSparkline: View {
    let series: [SeriesPoint]

    var body: some View {
        Chart(series) { point in
            BarMark(
                x: .value("时间", point.label),
                y: .value("成功", point.totals.calls - point.totals.errors)
            )
            .foregroundStyle(Color.accentColor.gradient)
            BarMark(x: .value("时间", point.label), y: .value("失败", point.totals.errors))
                .foregroundStyle(Color.red.gradient)
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
        .frame(height: 96)
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
                if row.failed {
                    Text(row.status > 0 ? "失败 \(row.status)" : "失败")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                } else if row.canceled {
                    Text("已取消")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
}

/// 一行里的一个 token 数：箭头加数字。不用 Label——它在这行的 HStack 里会把数字挤成竖排。
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
            Section("结果") {
                LabeledContent("状态", value: status)
                if let error = row.error, !error.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("用时", value: Format.duration(ms: row.millis))
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

    private var status: String {
        if row.canceled {
            return "Agent 取消"
        }
        if row.failed {
            return row.status > 0 ? "失败 \(row.status)" : "失败"
        }
        return row.status > 0 ? "成功 \(row.status)" : "成功"
    }
}
