import AppKit
import ImageIO

@MainActor
enum ImageCache {
    private static let imageCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        c.totalCostLimit = 50 * 1024 * 1024
        return c
    }()

    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 500
        c.totalCostLimit = 5 * 1024 * 1024
        return c
    }()

    static func image(at url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let img = NSImage(contentsOf: url) else { return nil }
        let cost = img.representations.first.map { Int($0.pixelsWide * $0.pixelsHigh * 4) } ?? 0
        imageCache.setObject(img, forKey: key, cost: cost)
        return img
    }

    static func thumbnail(at url: URL, maxPixelSize: Int = 88) -> NSImage? {
        let key = "\(url.path)|\(maxPixelSize)" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnailCache.setObject(img, forKey: key, cost: cg.width * cg.height * 4)
        return img
    }

    static func invalidate(_ url: URL) {
        imageCache.removeObject(forKey: url.path as NSString)
        for size in [88, 128, 256] {
            thumbnailCache.removeObject(forKey: "\(url.path)|\(size)" as NSString)
        }
    }

    static func clear() {
        imageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }
}
