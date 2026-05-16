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
        guard let literal = URLSafetyGate.parseIPLiteral(host) else { return false }
        return URLSafetyGate.isBlockedAddress(literal)
    }
}
