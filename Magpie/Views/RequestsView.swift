import SwiftUI

/// 这把密钥自己的调用记录，最新的在前，往下翻自动加载下一页。
struct RequestsView: View {
    let session: Session

    @State private var period = UsagePeriod.week
    @State private var rows: [RequestRow] = []
    @State private var total = 0
    @State private var totals = UsageTotals()
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
                Label(Format.tokens(row.input), systemImage: "arrow.up")
                Label(Format.tokens(row.output), systemImage: "arrow.down")
                if row.cacheRead > 0 {
                    Label(Format.tokens(row.cacheRead), systemImage: "bolt")
                }
                Spacer()
                if row.priced {
                    Text("约 \(Format.usd(row.cost))")
                }
                Text(Format.duration(ms: row.millis))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
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
