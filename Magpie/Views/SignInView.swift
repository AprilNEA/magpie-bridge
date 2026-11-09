import SwiftUI

struct SignInView: View {
    let session: Session

    @State private var address: String
    @State private var key = ""
    @State private var working = false
    @State private var failure: String?
    @FocusState private var focus: Field?

    private enum Field {
        case address, key
    }

    init(session: Session) {
        self.session = session
        _address = State(initialValue: session.lastAddress ?? Self.defaultAddress)
    }

    /// Gateway address prefilled for this build; see Config/Local.xcconfig.
    static var defaultAddress: String {
        Bundle.main.object(forInfoDictionaryKey: "MagpieDefaultGatewayURL") as? String ?? ""
    }

    private var canSubmit: Bool {
        !working && !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://magpie.example.com", text: $address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { focus = .key }
                        .accessibilityIdentifier("signin.address")
                } header: {
                    Text("网关地址")
                } footer: {
                    Text("输入你拿到的网关密钥，查看它的用量、可用的模型，以及如何配置你的 Agent。")
                }
                Section {
                    SecureField("sk-magpie-key-…", text: $key)
                        // 不是账号密码，别让系统在登录后弹「存储密码？」。
                        .textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .key)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .accessibilityIdentifier("signin.key")
                } header: {
                    Text("网关密钥")
                } footer: {
                    Text("密钥只保存在这台设备的钥匙串里，只会发送给这个网关。")
                }
                Section {
                    Button(action: submit) {
                        HStack {
                            Text("继续")
                            if working {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("signin.continue")
                } footer: {
                    if let failure {
                        Text(failure)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("signin.error")
                    }
                }
            }
            .navigationTitle("你的网关密钥")
            .onAppear {
                focus = address.isEmpty ? .address : .key
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        working = true
        failure = nil
        Task {
            defer { working = false }
            do {
                try await session.signIn(address: address, key: key)
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
