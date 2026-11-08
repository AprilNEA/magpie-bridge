import SwiftUI

struct SettingsView: View {
    let session: Session

    @State private var limit: KeyLimit?
    @State private var confirmForget = false

    var body: some View {
        Form {
            Section("网关") {
                LabeledContent("地址", value: session.credential?.baseURL.absoluteString ?? "")
                LabeledContent("密钥", value: session.info?.name ?? "—")
                if let version = session.info?.version, !version.isEmpty {
                    LabeledContent("网关版本", value: version)
                }
            }
            if let limit {
                Section("密钥限制") {
                    LabeledContent(
                        "受限于",
                        value: limit.heldTo.isEmpty
                            ? "无" : limit.heldToTitles.joined(separator: "、"))
                    if !limit.models.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("可用模型")
                            Text(limit.models.joined(separator: "  "))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let expires = limit.expires {
                        LabeledContent("过期", value: Format.when(expires))
                    }
                }
            }
            Section {
                Button("忘记密钥", role: .destructive) { confirmForget = true }
                    .accessibilityIdentifier("settings.forget")
            } footer: {
                Text("从这台设备的钥匙串里删除密钥，回到输入页。网关地址会留着。")
            }
            Section("关于") {
                LabeledContent("版本", value: Self.appVersion)
                if let url = URL(string: "https://github.com/AprilNEA/magpie-ios") {
                    Link("源代码", destination: url)
                }
            }
        }
        .navigationTitle("设置")
        .task {
            guard let client = session.client else { return }
            limit = try? await client.limit()
        }
        .confirmationDialog("忘记这个密钥？", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("确定忘记", role: .destructive) { session.signOut() }
        } message: {
            Text("之后要再输入一次密钥才能查看。")
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
