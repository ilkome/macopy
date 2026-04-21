import AppKit

@MainActor
enum ImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        c.totalCostLimit = 50 * 1024 * 1024
        return c
    }()

    static func image(at url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let img = NSImage(contentsOf: url) else { return nil }
        let size = img.representations.first.map { Int($0.pixelsWide * $0.pixelsHigh * 4) } ?? 0
        cache.setObject(img, forKey: key, cost: size)
        return img
    }

    static func invalidate(_ url: URL) {
        cache.removeObject(forKey: url.path as NSString)
    }

    static func clear() {
        cache.removeAllObjects()
    }
}
