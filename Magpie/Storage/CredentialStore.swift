import Foundation
import Security

/// The gateway address lives in UserDefaults and the key in the Keychain, one per gateway address.
struct CredentialStore {
    static let service = "com.aprilnea.queqiao.gateway-key"
    /// The gateway address used last. The launch argument -gatewayAddress can also provide it
    /// (for UI tests).
    static let addressKey = "gatewayAddress"

    private let items: any KeychainItems
    private let defaults: UserDefaults

    init() {
        self.init(items: Keychain(), defaults: .standard)
    }

    init(items: any KeychainItems, defaults: UserDefaults) {
        self.items = items
        self.defaults = defaults
    }

    var address: String? {
        defaults.string(forKey: Self.addressKey)
    }

    func load() -> Credential? {
        guard let address, let url = URL(string: address),
            let data = try? items.read(account: address), !data.isEmpty
        else { return nil }
        return Credential(baseURL: url, key: String(decoding: data, as: UTF8.self))
    }

    func save(_ credential: Credential) throws(KeychainFailure) {
        let account = credential.baseURL.absoluteString
        try items.write(Data(credential.key.utf8), account: account)
        defaults.set(account, forKey: Self.addressKey)
    }

    /// Deletes the key; the address stays, so next time only the key needs entering again.
    func forgetKey() throws(KeychainFailure) {
        guard let address else { return }
        try items.delete(account: address)
    }
}

nonisolated struct KeychainFailure: Error, Equatable {
    let status: OSStatus
}

nonisolated extension KeychainFailure: LocalizedError {
    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String?
    }
}

/// Generic password items accessed by account. Tests swap in an in-memory implementation.
protocol KeychainItems {
    func read(account: String) throws(KeychainFailure) -> Data?
    /// Replaces the item when present, otherwise creates it.
    func write(_ data: Data, account: String) throws(KeychainFailure)
    /// Deleting an item that does not exist also counts as success.
    func delete(account: String) throws(KeychainFailure)
}

struct Keychain: KeychainItems {
    func read(account: String) throws(KeychainFailure) -> Data? {
        var query = Self.query(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainFailure(status: status)
        }
        return result as? Data
    }

    func write(_ data: Data, account: String) throws(KeychainFailure) {
        let query = Self.query(account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw KeychainFailure(status: status)
        }
        var item = query
        item[kSecValueData] = data
        // Readable only when unlocked and only on this device: the key stays out of iCloud Keychain
        // and must be entered again on a new device.
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else {
            throw KeychainFailure(status: added)
        }
    }

    func delete(account: String) throws(KeychainFailure) {
        let status = SecItemDelete(Self.query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainFailure(status: status)
        }
    }

    private static func query(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: CredentialStore.service,
            kSecAttrAccount: account,
        ]
    }
}
