import AppKit

/// Small, bounded cache of decoded favicons keyed by hostname. Domain rows pull from here
/// instead of holding every preview's icon blob resident in `ClipboardStore.previewsByHash`.
@MainActor
enum FaviconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 500
        c.totalCostLimit = 8 * 1024 * 1024
        return c
    }()

    static func load(hostname: String) async -> NSImage? {
        let key = hostname as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let data = await Task.detached(priority: .userInitiated) {
            try? LinkPreviewRepository.iconData(forHostname: hostname)
        }.value
        guard let data, let img = NSImage(data: data) else { return nil }
        let cost = img.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? data.count
        cache.setObject(img, forKey: key, cost: cost)
        return img
    }
}
