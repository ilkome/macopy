import CryptoKit
import Foundation

enum URLNormalizer {
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    static func hash(_ raw: String) -> String {
        let normalized = normalize(raw)
        let data = Data(normalized.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func shouldFetchPreview(_ raw: String) -> Bool {
        guard let url = parse(raw) else { return false }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" { return false }
        if host.hasSuffix(".local") { return false }
        if host.hasSuffix(".onion") { return false }
        if host.hasSuffix(".internal") { return false }
        if !host.contains(".") { return false }
        if isPrivateIP(host) { return false }
        return true
    }

    static func normalizedHost(_ raw: String) -> String? {
        guard var host = parse(raw)?.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host.isEmpty ? nil : host
    }

    static func parse(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded), url.scheme != nil {
            return url
        }
        return nil
    }

    private static func isPrivateIP(_ host: String) -> Bool {
        if host == "127.0.0.1" || host == "::1" || host == "0.0.0.0" { return true }
        let parts = host.split(separator: ".")
        guard parts.count == 4, let a = Int(parts[0]), let b = Int(parts[1]) else {
            return false
        }
        if a == 10 { return true }
        if a == 127 { return true }
        if a == 192 && b == 168 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        if a == 169 && b == 254 { return true }
        return false
    }
}
