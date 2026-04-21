import AppKit

@MainActor
enum ImageCache {
    private static var cache: [String: NSImage] = [:]

    static func image(at url: URL) -> NSImage? {
        let key = url.path
        if let cached = cache[key] { return cached }
        guard let img = NSImage(contentsOf: url) else { return nil }
        cache[key] = img
        return img
    }

    static func invalidate(_ url: URL) {
        cache.removeValue(forKey: url.path)
    }

    static func clear() {
        cache.removeAll()
    }
}
