import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum ImageCache {
    /// Pixel size of the small encrypted thumbnail persisted next to each clipboard image.
    /// Generous enough to also serve modest previews; on a row miss we read this (~tens of KB)
    /// instead of decrypting + decoding the full-resolution original.
    nonisolated static let thumbStorePixelSize = 256

    nonisolated static func thumbFilename(for filename: String) -> String { filename + ".thumb" }

    private static let imageCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        c.totalCostLimit = 50 * 1024 * 1024
        return c
    }()

    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 1600
        c.totalCostLimit = 50 * 1024 * 1024
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

    /// Cache-only lookup (no disk/decode). Lets a row render an already-decoded thumbnail
    /// synchronously without flashing a placeholder.
    static func cachedThumbnail(filename: String, maxPixelSize: Int = 88) -> NSImage? {
        thumbnailCache.object(forKey: "\(filename)|\(maxPixelSize)" as NSString)
    }

    /// Async row-thumbnail load. Returns immediately on a cache hit; otherwise decodes
    /// off-main (reading the tiny persisted thumb, or the original as a fallback) and caches
    /// the result on the main actor.
    static func loadThumbnail(filename: String, maxPixelSize: Int = 88) async -> NSImage? {
        let key = "\(filename)|\(maxPixelSize)" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) {
            loadThumbnailDecoded(filename: filename, maxPixelSize: maxPixelSize)
        }.value
        guard let decoded else { return nil }
        thumbnailCache.setObject(decoded.image, forKey: key, cost: decoded.cost)
        return decoded.image
    }

    /// Reads the persisted `.thumb` (~tens of KB) and decodes it to `maxPixelSize`. For older
    /// items written before thumbnails existed, falls back to the original and lazily persists
    /// a thumb so the next miss is cheap. Call off-main.
    nonisolated private static func loadThumbnailDecoded(filename: String, maxPixelSize: Int) -> Decoded? {
        let thumbName = thumbFilename(for: filename)
        if let data = try? ImageStore.read(filename: thumbName),
           let decoded = decodeDownsampled(data, maxPixelSize: maxPixelSize) {
            return decoded
        }
        guard let original = try? ImageStore.read(filename: filename) else { return nil }
        if let thumbData = encodedThumbnail(from: original, maxPixelSize: thumbStorePixelSize) {
            try? ImageStore.write(thumbData, filename: thumbName)
        }
        return decodeDownsampled(original, maxPixelSize: maxPixelSize)
    }

    /// Downsamples `data` to `maxPixelSize` and PNG-encodes it (PNG to preserve any alpha).
    /// Produces the small payload persisted as the `.thumb` companion file.
    nonisolated static func encodedThumbnail(from data: Data, maxPixelSize: Int) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    nonisolated private static func decodeDownsampled(_ data: Data, maxPixelSize: Int) -> Decoded? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return Decoded(
            image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)),
            cost: cg.width * cg.height * 4
        )
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
        let cost: Int
    }

    /// Off-main decode: reads + downsamples to maxPixelSize without ever materializing the
    /// full-resolution bitmap. Call from a detached task; cache the result on the main actor.
    nonisolated static func downsampledImage(filename: String, maxPixelSize: Int) -> Decoded? {
        guard let data = try? ImageStore.read(filename: filename) else { return nil }
        return decodeDownsampled(data, maxPixelSize: maxPixelSize)
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
