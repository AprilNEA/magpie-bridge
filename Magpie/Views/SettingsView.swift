import SwiftUI

/// 网关、密钥受到的限制（/v1/magpie/limit 的全部内容）、忘记密钥、关于。
struct SettingsView: View {
    let session: Session

    @State private var limit: KeyLimit?
    @State private var limitError: String?
    @State private var confirmForget = false

    var body: some View {
        Form {
            gateway
            if let limit {
                restrictions(limit)
                if !limit.issuerLimits.isEmpty {
                    issuerLimits(limit.issuerLimits)
                }
            } else {
                Section("密钥限制") {
                    if let limitError {
                        Label(limitError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        ProgressView()
                    }
                }
            }
            Section {
                Button("忘记密钥", role: .destructive) { confirmForget = true }
                    .accessibilityIdentifier("settings.forget")
            } footer: {
                Text("从这台设备的钥匙串里删除密钥，回到输入页。网关地址会留着。")
            }
            about
        }
        .navigationTitle("设置")
        .task { await loadLimit() }
        .refreshable {
            await session.refresh()
            await loadLimit()
        }
        .confirmationDialog("忘记这个密钥？", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("确定忘记", role: .destructive) { session.signOut() }
        } message: {
            Text("之后要再输入一次密钥才能查看。")
        }
    }

    private var gateway: some View {
        Section("网关") {
            if let address = session.credential?.baseURL.absoluteString {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("地址")
                        Text(address)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    CopyButton(text: address)
                }
            }
            LabeledContent("密钥", value: session.info?.name ?? "—")
            if let version = session.info?.version, !version.isEmpty {
                LabeledContent("网关版本", value: version)
            }
            if let refreshedAt = session.refreshedAt {
                LabeledContent("上次刷新", value: Format.when(refreshedAt))
            }
        }
    }

    private func restrictions(_ limit: KeyLimit) -> some View {
        Section {
            LabeledContent(
                "受限于",
                value: limit.heldTo.isEmpty ? "无" : limit.heldToTitles.joined(separator: "、"))
            ForEach(limit.limits) { status in
                LimitRow(limit: status)
                    .accessibilityIdentifier("settings.limit")
            }
            if !limit.models.isEmpty {
                list("可用模型", limit.models)
            }
            if !limit.heldTo.isEmpty {
                LabeledContent("账号配额", value: quotasText(limit))
            }
            switch limit.mcpAccess {
            case .every:
                LabeledContent("MCP 服务器", value: "全部")
            case .none:
                LabeledContent("MCP 服务器", value: "无")
            case .some(let entries):
                list("MCP 服务器", entries)
            }
            if let expires = limit.expires {
                LabeledContent("过期", value: Format.when(expires))
            }
        } header: {
            Text("密钥限制")
        } footer: {
            if !limit.heldTo.isEmpty {
                Text("受限的密钥看不到这个网关的账号，只看到自己的用量和这里列出的限制。")
            }
        }
    }

    private func issuerLimits(_ limits: [LimitStatus]) -> some View {
        Section {
            ForEach(limits) { status in
                LimitRow(limit: status)
                    .accessibilityIdentifier("settings.issuerLimit")
            }
        } header: {
            Text("签发者的额度")
        } footer: {
            Text("这把密钥由另一把受限的密钥签发。签发者的额度把它签出去的所有密钥一起算，用完了这把也会被拒。")
        }
    }

    private var about: some View {
        Section("关于") {
            LabeledContent("版本", value: Self.appVersion)
            link("源代码", "https://github.com/AprilNEA/magpie-bridge")
            link("反馈问题", "https://github.com/AprilNEA/magpie-bridge/issues")
            link("magpie 网关", "https://github.com/yetone/magpie")
        }
    }

    /// 一行标题，下面每个名字各占一行等宽小字（模型通配、MCP 条目），免得长名字从中间折行。
    private func list(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(items.joined(separator: "\n"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func link(_ title: String, _ address: String) -> some View {
        if let url = URL(string: address) {
            Link(title, destination: url)
        }
    }

    /// 受限的密钥能不能看到账号的配额，能的话是哪些提供方的。
    private func quotasText(_ limit: KeyLimit) -> String {
        guard limit.quotas else { return "不可见" }
        return limit.quotaProviders.isEmpty ? "可见" : limit.quotaProviders.joined(separator: "、")
    }

    private func loadLimit() async {
        guard let client = session.client else { return }
        do {
            limit = try await client.limit()
            limitError = nil
        } catch {
            limitError = error.localizedDescription
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
