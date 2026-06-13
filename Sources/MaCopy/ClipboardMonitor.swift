import AppKit
import CryptoKit
import ImageIO
import os

@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "heic", "webp"]
    private static let privacyLogger = Logger(subsystem: "dev.ilkome.MaCopy", category: "privacy.filter")

    private static let allowedImageRoots: [String] = {
        let fm = FileManager.default
        let dirs: [FileManager.SearchPathDirectory] = [
            .documentDirectory, .desktopDirectory, .downloadsDirectory, .picturesDirectory
        ]
        return dirs.compactMap { dir in
            (try? fm.url(for: dir, in: .userDomainMask, appropriateFor: nil, create: false))?
                .resolvingSymlinksInPath().standardizedFileURL.path
        }
    }()

    static func isAllowedImageFileURL(_ url: URL, allowedRoots: [String]? = nil) -> Bool {
        guard url.isFileURL else { return false }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        let roots = allowedRoots ?? allowedImageRoots
        for root in roots {
            if resolved == root || resolved.hasPrefix(root + "/") {
                return true
            }
        }
        return false
    }

    private init() {}

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        let t = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in
                ClipboardMonitor.shared.poll()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if PrivacyFilter.shouldIgnore(pb) { return }

        let frontApp = NSWorkspace.shared.frontmostApplication
        // Skip if our own app owns the paste (copying from our panel shouldn't add)
        if frontApp?.bundleIdentifier == Bundle.main.bundleIdentifier,
           frontApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return
        }

        let types = Set(pb.types ?? [])
        let fileURLs = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []

        if let (data, ext) = readImageData(from: pb, types: types, fileURLs: fileURLs) {
            handleImage(
                data: data,
                ext: ext,
                fileURL: fileURLs.first,
                frontApp: frontApp
            )
            return
        }

        if !fileURLs.isEmpty {
            let text = fileURLs.map { $0.path }.joined(separator: "\n")
            handleText(text, sourceFile: fileURLs.first?.path, frontApp: frontApp)
            return
        }

        if let text = pb.string(forType: .string), !text.isEmpty {
            if AppSettings.shared.filterSensitiveContent,
               let kind = SecretDetector.detect(in: String(text.prefix(Self.detectionScanCap))) {
                Self.privacyLogger.info("filtered: \(kind.rawValue, privacy: .public)")
                return
            }
            handleText(text, sourceFile: nil, frontApp: frontApp)
        }
    }

    private func readImageData(
        from pb: NSPasteboard,
        types: Set<NSPasteboard.PasteboardType>,
        fileURLs: [URL]
    ) -> (Data, String)? {
        if types.contains(.png), let data = pb.data(forType: .png) { return (data, "png") }
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")
        if types.contains(jpegType), let data = pb.data(forType: jpegType) { return (data, "jpg") }
        if types.contains(.tiff), let data = pb.data(forType: .tiff) { return (data, "tiff") }
        if let first = fileURLs.first {
            let ext = first.pathExtension.lowercased()
            guard imageExts.contains(ext) else { return nil }
            guard Self.isAllowedImageFileURL(first) else {
                Self.privacyLogger.info("rejected: file image outside allowed roots")
                return nil
            }
            if let data = try? Data(contentsOf: first) {
                return (data, ext)
            }
        }
        return nil
    }

    // Type/secret detection scan multiple times over the payload; on a multi-MB clip that is
    // hundreds of MB of main-thread scanning. URLs are < 2048 chars and code/secret signals sit
    // at the start, so bound detection to a prefix. Hashing stays over the full payload so dedup
    // never collides two long clips that share a prefix.
    private static let detectionScanCap = 256 * 1024

    private func handleText(_ text: String, sourceFile: String?, frontApp: NSRunningApplication?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let scanText = String(text.prefix(Self.detectionScanCap))
        let kind = ContentTypeDetector.detect(scanText)
        let hashInput = kind == .url ? URLNormalizer.normalize(text) : text
        let hash = Self.sha256(Data(hashInput.utf8))

        if let existing = try? ClipboardItemRepository.findItem(byHash: hash) {
            try? ClipboardItemRepository.updateUpdatedAt(id: existing.id)
            if kind == .url {
                LinkPreviewService.shared.fetchIfNeeded(for: text)
            }
            return
        }

        let preview = String(text.prefix(200))
        let iconPath = frontApp.flatMap { IconCache.savedIcon(for: $0) }

        let item = ClipboardItemRecord(
            contentHash: hash,
            kind: kind,
            text: text,
            preview: preview,
            sourceAppBundleId: frontApp?.bundleIdentifier,
            sourceAppName: frontApp?.localizedName,
            sourceAppIconPath: iconPath,
            sourceFilePath: sourceFile,
            byteSize: text.utf8.count
        )
        try? ClipboardItemRepository.insertItem(item)

        if kind == .url {
            LinkPreviewService.shared.fetchIfNeeded(for: text)
        }
    }

    private func handleImage(
        data: Data,
        ext: String,
        fileURL: URL?,
        frontApp: NSRunningApplication?
    ) {
        let hash = Self.hashImage(data)

        if let existing = try? ClipboardItemRepository.findItem(byHash: hash) {
            try? ClipboardItemRepository.updateUpdatedAt(id: existing.id)
            return
        }

        let filename = "\(UUID().uuidString).\(ext)"
        do { try ImageStore.write(data, filename: filename) } catch { return }

        // Persist a small encrypted thumbnail off-main so row rendering reads ~tens of KB on a
        // cache miss instead of decrypting + decoding the full-resolution original.
        Task.detached(priority: .utility) {
            if let thumbData = ImageCache.encodedThumbnail(from: data, maxPixelSize: ImageCache.thumbStorePixelSize) {
                try? ImageStore.write(thumbData, filename: ImageCache.thumbFilename(for: filename))
            }
        }

        let (width, height) = Self.dimensions(from: data)
        let iconPath = frontApp.flatMap { IconCache.savedIcon(for: $0) }
        let preview = fileURL?.lastPathComponent ?? "Image \(width)×\(height)"

        let item = ClipboardItemRecord(
            contentHash: hash,
            kind: .image,
            preview: preview,
            imagePath: filename,
            imageWidth: width,
            imageHeight: height,
            sourceAppBundleId: frontApp?.bundleIdentifier,
            sourceAppName: frontApp?.localizedName,
            sourceAppIconPath: iconPath,
            sourceFilePath: fileURL?.path,
            byteSize: data.count
        )
        try? ClipboardItemRepository.insertItem(item)

        if AppSettings.shared.ocrEnabled {
            let id = item.id
            let filterSecrets = AppSettings.shared.filterSensitiveContent
            Task.detached(priority: .utility) {
                await OCRService.process(itemId: id, imagePath: filename, filterSecrets: filterSecrets)
            }
        }
    }

    private static func dimensions(from data: Data) -> (Int, Int) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return (0, 0) }
        return (w, h)
    }

    private static func hashImage(_ data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: data.prefix(64 * 1024))
        var size = UInt64(data.count)
        withUnsafeBytes(of: &size) { hasher.update(bufferPointer: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
