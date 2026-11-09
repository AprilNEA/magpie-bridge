import Foundation

/// A gateway and the key used with it.
nonisolated struct Credential: Hashable, Sendable {
    var baseURL: URL
    var key: String

    /// The gateway address as the user typed it: https:// may be omitted, and a /me or /v1 copied
    /// from the browser's address bar may be left on.
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
