import Foundation
import Security

/// 网关地址放在 UserDefaults，密钥放在钥匙串，按网关地址区分。
struct CredentialStore {
    static let service = "com.aprilnea.magpie.gateway-key"
    /// 最近一次用的网关地址。启动参数 -gatewayAddress 也能给出（UI 测试用）。
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

    /// 删掉密钥；地址留着，下次只需再输入密钥。
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

/// 按账号存取的通用密码项。测试换成内存实现。
protocol KeychainItems {
    func read(account: String) throws(KeychainFailure) -> Data?
    /// 有就替换，没有就新建。
    func write(_ data: Data, account: String) throws(KeychainFailure)
    /// 删除不存在的项也算成功。
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
        // 只在解锁后、只在这台设备上可读：密钥不进 iCloud 钥匙串，换机要重新输入。
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
