import Foundation
import Observation

/// 当前登录的网关密钥和它最近一次 /me 的结果。
@Observable
final class Session {
    private(set) var credential: Credential?
    private(set) var info: KeyInfo?
    /// info 是什么时候拿到的。
    private(set) var refreshedAt: Date?
    private(set) var isRefreshing = false
    /// 最近一次刷新失败的原因；成功后清除。
    private(set) var refreshError: String?

    private let store: CredentialStore
    private let transport: any Transport

    init(store: CredentialStore = CredentialStore(), transport: any Transport = URLSession.shared) {
        self.store = store
        self.transport = transport
        credential = store.load()
    }

    var client: MagpieClient? {
        credential.map { MagpieClient(baseURL: $0.baseURL, key: $0.key, transport: transport) }
    }

    /// 登录页预填的地址：上次用过的，否则工程里配置的默认网关。
    var lastAddress: String? {
        store.address
    }

    nonisolated enum SignInFailure: Error, Equatable, LocalizedError {
        case badAddress
        case gateway(MagpieError)
        case keychain(KeychainFailure)

        var errorDescription: String? {
            switch self {
            case .badAddress: "网关地址要是 http(s) 地址，例如 https://magpie.example.com。"
            case .gateway(let error): error.errorDescription
            case .keychain(let error): "没能保存密钥：\(error.localizedDescription)"
            }
        }
    }

    /// 先用 /v1/magpie/me 验证密钥，通过才保存。
    func signIn(address: String, key: String) async throws(SignInFailure) {
        guard let url = Credential.gatewayURL(from: address) else {
            throw .badAddress
        }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = MagpieClient(baseURL: url, key: key, transport: transport)
        let info: KeyInfo
        do {
            info = try await client.me()
        } catch {
            throw .gateway(error)
        }
        let credential = Credential(baseURL: url, key: key)
        do {
            try store.save(credential)
        } catch {
            throw .keychain(error)
        }
        self.credential = credential
        self.info = info
        refreshedAt = Date()
        refreshError = nil
    }

    func refresh() async {
        guard let client, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            info = try await client.me()
            refreshedAt = Date()
            refreshError = nil
        } catch MagpieError.invalidKey {
            // 密钥被停用或删除：和网页一样回到输入页。
            signOut()
        } catch {
            refreshError = error.localizedDescription
        }
    }

    func signOut() {
        try? store.forgetKey()
        credential = nil
        info = nil
        refreshedAt = nil
        refreshError = nil
    }
}
