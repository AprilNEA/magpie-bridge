import Foundation

/// 一个网关和在它那里用的密钥。
nonisolated struct Credential: Hashable, Sendable {
    var baseURL: URL
    var key: String

    /// 用户输入的网关地址：可以省略 https://，也可以带着从浏览器地址栏复制来的 /me 或 /v1。
    static func gatewayURL(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard var parts = URLComponents(string: text),
            let host = parts.host, !host.isEmpty,
            parts.scheme == "https" || parts.scheme == "http"
        else { return nil }
        parts.query = nil
        parts.fragment = nil
        var path = parts.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        for tail in ["/me", "/v1"] where path.hasSuffix(tail) {
            path.removeLast(tail.count)
        }
        while path.hasSuffix("/") {
            path.removeLast()
        }
        parts.path = path
        return parts.url
    }
}
