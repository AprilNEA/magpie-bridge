import SwiftUI

/// 网页 /me 的上半部分：额度、用量、最常用的模型。
struct OverviewView: View {
    let session: Session

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
                        Button("重试") { Task { await session.refresh() } }
                    }
                }
            }
        }
        .navigationTitle(session.info?.name ?? "概览")
        .refreshable { await session.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise") {
                    Task { await session.refresh() }
                }
                .disabled(session.isRefreshing)
            }
        }
    }

    private func limits(_ info: KeyInfo) -> some View {
        Section("额度") {
            if info.limits.isEmpty {
                Text("这个密钥没有额度限制。").foregroundStyle(.secondary)
            }
            ForEach(info.limits) { limit in
                LimitRow(limit: limit)
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

    private func topModels(_ info: KeyInfo) -> some View {
        Section("最近 30 天最常用") {
            if info.topModels.isEmpty {
                Text("还没有用量。").foregroundStyle(.secondary)
            }
            ForEach(info.topModels) { model in
                HStack {
                    Text(model.id)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(
                        "\(Format.count(model.totals.calls)) 次 · \(Format.tokens(model.totals.tokens)) tokens"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
        }
    }
}

private struct LimitRow: View {
    let limit: LimitStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(limit.title).font(.headline)
                Spacer()
                if limit.spent {
                    Text("已用完，重置后恢复")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
            if let cap = limit.costLimit, cap > 0 {
                bar(
                    fraction: limit.cost / cap,
                    text: "已用 \(Format.usd(limit.cost)) / \(Format.usd(cap))")
            }
            if let cap = limit.tokenLimit, cap > 0 {
                bar(
                    fraction: Double(limit.tokens) / Double(cap),
                    text: "已用 \(Format.tokens(limit.tokens)) / \(Format.tokens(cap)) tokens")
            }
            if let reset = limit.resetsAt {
                Text("\(Format.when(reset)) 重置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func bar(fraction: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(fraction >= 1 ? Color.red : Color.accentColor)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
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
