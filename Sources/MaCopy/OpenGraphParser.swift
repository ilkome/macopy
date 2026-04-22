import Foundation

struct OpenGraphMetadata: Sendable {
    var title: String?
    var description: String?
    var siteName: String?
    var imageURL: URL?
}

enum OpenGraphParser {
    static func fetch(url: URL, timeout: TimeInterval = 6) async -> OpenGraphMetadata? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = (try? await URLSession.shared.data(for: request)) ?? (Data(), URLResponse())
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            return nil
        }
        let encoding = Self.encoding(from: http, data: data)
        let slice = data.prefix(256 * 1024)
        guard let html = String(data: slice, encoding: encoding) ?? String(data: slice, encoding: .utf8)
        else { return nil }
        return parse(html: html, baseURL: url)
    }

    static func parse(html: String, baseURL: URL) -> OpenGraphMetadata {
        var result = OpenGraphMetadata()
        let head = headSlice(html)

        let tags = extractMetaTags(head)
        for tag in tags {
            let key = tag.name.lowercased()
            let value = decodeEntities(tag.content)
            switch key {
            case "og:title", "twitter:title":
                if result.title == nil { result.title = value }
            case "og:description", "twitter:description", "description":
                if result.description == nil { result.description = value }
            case "og:site_name":
                if result.siteName == nil { result.siteName = value }
            case "og:image", "og:image:url", "og:image:secure_url", "twitter:image":
                if result.imageURL == nil {
                    result.imageURL = URL(string: value, relativeTo: baseURL)?.absoluteURL
                }
            default:
                break
            }
        }

        if result.title == nil, let t = extractTitle(head) {
            result.title = decodeEntities(t)
        }
        return result
    }

    private static func headSlice(_ html: String) -> String {
        let lower = html.lowercased()
        if let start = lower.range(of: "<head"), let end = lower.range(of: "</head>") {
            return String(html[start.lowerBound..<end.upperBound])
        }
        return String(html.prefix(64 * 1024))
    }

    private struct MetaTag {
        let name: String
        let content: String
    }

    private static func extractMetaTags(_ head: String) -> [MetaTag] {
        var out: [MetaTag] = []
        let nsHead = head as NSString
        guard let regex = try? NSRegularExpression(
            pattern: "<meta\\b([^>]*)/?>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(location: 0, length: nsHead.length)
        regex.enumerateMatches(in: head, options: [], range: range) { match, _, _ in
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

    private static func attributeValue(_ attrs: String, key: String) -> String? {
        let patterns = [
            "\(key)\\s*=\\s*\"([^\"]*)\"",
            "\(key)\\s*=\\s*'([^']*)'",
            "\(key)\\s*=\\s*([^\\s>]+)"
        ]
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive])
            else { continue }
            let ns = attrs as NSString
            if let m = regex.firstMatch(in: attrs, range: NSRange(location: 0, length: ns.length)),
               m.numberOfRanges >= 2 {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }

    private static func extractTitle(_ head: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<title[^>]*>([\\s\\S]*?)</title>",
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = head as NSString
        guard let m = regex.firstMatch(in: head, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        let raw = ns.substring(with: m.range(at: 1))
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }

    private static func encoding(from response: HTTPURLResponse, data: Data) -> String.Encoding {
        if let name = response.textEncodingName {
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId {
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            }
        }
        return .utf8
    }
}
