import Foundation

enum HTMLMetaTagParser {
    struct MetaTag {
        let name: String
        let content: String
    }

    static func extractMetaTags(_ head: String) -> [MetaTag] {
        var out: [MetaTag] = []
        let nsHead = head as NSString
        let range = NSRange(location: 0, length: nsHead.length)
        metaTagRegex.enumerateMatches(in: head, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let attrs = nsHead.substring(with: match.range(at: 1))
            let name = attributeValue(attrs, key: "property")
                ?? attributeValue(attrs, key: "name")
                ?? attributeValue(attrs, key: "itemprop")
            let content = attributeValue(attrs, key: "content")
            if let name, let content, !content.isEmpty {
                out.append(MetaTag(name: name, content: content))
            }
        }
        return out
    }

    static func extractTitle(_ head: String) -> String? {
        let ns = head as NSString
        guard let m = titleRegex.firstMatch(in: head, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        let raw = ns.substring(with: m.range(at: 1))
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func headSlice(_ html: String) -> String {
        let lower = html.lowercased()
        if let start = lower.range(of: "<head"), let end = lower.range(of: "</head>") {
            return String(html[start.lowerBound..<end.upperBound])
        }
        return String(html.prefix(64 * 1024))
    }

    static func decodeEntities(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let metaTagRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: "<meta\\b([^>]*)/?>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }()

    private static let titleRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: "<title[^>]*>([\\s\\S]*?)</title>",
            options: [.caseInsensitive]
        )
    }()

    private static let attrRegexCache: [String: [NSRegularExpression]] = {
        let keys = ["property", "name", "itemprop", "content"]
        var dict: [String: [NSRegularExpression]] = [:]
        for key in keys {
            let patterns = [
                "\(key)\\s*=\\s*\"([^\"]*)\"",
                "\(key)\\s*=\\s*'([^']*)'",
                "\(key)\\s*=\\s*([^\\s>]+)"
            ]
            dict[key] = patterns.compactMap {
                try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
            }
        }
        return dict
    }()

    private static func attributeValue(_ attrs: String, key: String) -> String? {
        guard let regexes = attrRegexCache[key] else { return nil }
        let ns = attrs as NSString
        let range = NSRange(location: 0, length: ns.length)
        for regex in regexes {
            if let m = regex.firstMatch(in: attrs, range: range),
               m.numberOfRanges >= 2 {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }
}
