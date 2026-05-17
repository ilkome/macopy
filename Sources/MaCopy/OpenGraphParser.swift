import Foundation

struct OpenGraphMetadata: Sendable {
    var title: String?
    var description: String?
    var siteName: String?
    var imageURL: URL?
}

enum OpenGraphParser {
    static func fetch(url: URL, timeout: TimeInterval = 6) async -> OpenGraphMetadata? {
        guard let (data, response) = await SafeFetcher.fetch(
            url: url,
            maxBytes: 512 * 1024,
            accept: "text/html,application/xhtml+xml",
            timeout: timeout
        ) else { return nil }

        let encoding = Self.encoding(from: response, data: data)
        let slice = data.prefix(256 * 1024)
        guard let html = String(data: slice, encoding: encoding) ?? String(data: slice, encoding: .utf8)
        else { return nil }
        return parse(html: html, baseURL: url)
    }

    static func parse(html: String, baseURL: URL) -> OpenGraphMetadata {
        var result = OpenGraphMetadata()
        let head = HTMLMetaTagParser.headSlice(html)

        for tag in HTMLMetaTagParser.extractMetaTags(head) {
            let key = tag.name.lowercased()
            let value = HTMLMetaTagParser.decodeEntities(tag.content)
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

        if result.title == nil, let t = HTMLMetaTagParser.extractTitle(head) {
            result.title = HTMLMetaTagParser.decodeEntities(t)
        }
        return result
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
