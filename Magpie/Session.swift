import Foundation
import Observation

/// The currently signed-in gateway key and its most recent /me result.
@Observable
final class Session {
    private(set) var credential: Credential?
    private(set) var info: KeyInfo?
    /// When info was received.
    private(set) var refreshedAt: Date?
    private(set) var isRefreshing = false
    /// Why the most recent refresh failed; cleared after a success.
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

    /// Address prefilled on the sign-in page: the last one used, otherwise the default gateway
    /// configured in the project.
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

    /// Verifies the key with /v1/magpie/me first and saves it only once that passes.
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
            // The key was disabled or deleted: go back to the entry page, as the web page does.
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
