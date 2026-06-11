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

    // Preview-pane downsampled images (~880px, ~3MB each) get their own budget so they
    // don't evict the tiny 88px row thumbnails and vice versa.
    private static let previewCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 24
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    static func clipboardThumbnail(filename: String, maxPixelSize: Int = 88) -> NSImage? {
        let key = "\(filename)|\(maxPixelSize)" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let data = try? ImageStore.read(filename: filename),
              let src = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
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

    static func clipboardPreviewCached(filename: String, maxPixelSize: Int) -> NSImage? {
        previewCache.object(forKey: "\(filename)|\(maxPixelSize)" as NSString)
    }

    static func storeClipboardPreview(_ image: NSImage, filename: String, maxPixelSize: Int) {
        let cost = Int(image.size.width * image.size.height * 4)
        previewCache.setObject(image, forKey: "\(filename)|\(maxPixelSize)" as NSString, cost: cost)
    }

    /// Carries an NSImage decoded off-main back to the main actor. Safe because the image
    /// is created in the detached task and only ever read (never mutated) afterwards.
    struct Decoded: @unchecked Sendable {
        let image: NSImage
    }

    /// Off-main decode: reads + downsamples to maxPixelSize without ever materializing the
    /// full-resolution bitmap. Call from a detached task; cache the result on the main actor.
    nonisolated static func downsampledImage(filename: String, maxPixelSize: Int) -> Decoded? {
        guard let data = try? ImageStore.read(filename: filename),
              let src = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return Decoded(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
    }

    static func appIcon(filename: String) -> NSImage? {
        let url = Storage.iconURL(for: filename)
        let key = "icon|\(filename)" as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let img = NSImage(contentsOf: url) else { return nil }
        let cost = img.representations.first.map { Int($0.pixelsWide * $0.pixelsHigh * 4) } ?? 0
        imageCache.setObject(img, forKey: key, cost: cost)
        return img
    }

    static func invalidateClipboardImage(filename: String) {
        imageCache.removeObject(forKey: filename as NSString)
        for size in [88, 128, 256] {
            thumbnailCache.removeObject(forKey: "\(filename)|\(size)" as NSString)
        }
        previewCache.removeObject(forKey: "\(filename)|880" as NSString)
    }

    static func clear() {
        imageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        previewCache.removeAllObjects()
    }
}
