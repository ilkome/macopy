import AppKit
import CryptoKit
import ImageIO
import os

@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private var lastChangeCount: Int = 0
    private var timer: Timer?
    // Prune is O(scan) over the table; amortize it instead of running on every copy. Bounds
    // the DB to ~itemLimit + this threshold regardless of how long the app stays running.
    private var insertsSincePrune = 0
    private static let pruneEveryNInserts = 100
    private let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "heic", "webp"]
    private static let privacyLogger = Logger(subsystem: "dev.ilkome.MaCopy", category: "privacy.filter")
    nonisolated private static let storageLogger = Logger(
        subsystem: "dev.ilkome.MaCopy",
        category: "storage"
    )

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
    nonisolated private static let detectionScanCap = 256 * 1024

    private func handleText(_ text: String, sourceFile: String?, frontApp: NSRunningApplication?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // IconCache is @MainActor, so resolve app metadata here; the full-payload SHA256, dedup
        // and insert run off the main thread (a multi-MB clip otherwise freezes the panel/paste).
        let iconPath = frontApp.flatMap { IconCache.savedIcon(for: $0) }
        let bundleId = frontApp?.bundleIdentifier
        let appName = frontApp?.localizedName

        Task.detached(priority: .userInitiated) {
            let scanText = String(text.prefix(Self.detectionScanCap))
            let kind = ContentTypeDetector.detect(scanText)
            let hashInput = kind == .url ? URLNormalizer.normalize(text) : text
            let hash = Self.sha256(Data(hashInput.utf8))

            let item = ClipboardItemRecord(
                contentHash: hash,
                kind: kind,
                text: text,
                preview: String(text.prefix(200)),
                sourceAppBundleId: bundleId,
                sourceAppName: appName,
                sourceAppIconPath: iconPath,
                sourceFilePath: sourceFile,
                byteSize: text.utf8.count
            )
            do {
                let result = try ClipboardItemRepository.insertOrRecordObservedCopy(item)
                await MainActor.run {
                    if result.inserted { ClipboardMonitor.shared.notePotentialPrune() }
                    if kind == .url { LinkPreviewService.shared.fetchIfNeeded(for: text) }
                }
            } catch {
                Self.storageLogger.error("observed text copy persistence failed: \(error, privacy: .private)")
            }
        }
    }

    private func handleImage(
        data: Data,
        ext: String,
        fileURL: URL?,
        frontApp: NSRunningApplication?
    ) {
        let hash = Self.hashImage(data)

        let filename = "\(UUID().uuidString).\(ext)"
        let iconPath = frontApp.flatMap { IconCache.savedIcon(for: $0) }  // @MainActor
        let bundleId = frontApp?.bundleIdentifier
        let appName = frontApp?.localizedName
        let sourcePath = fileURL?.path
        let previewName = fileURL?.lastPathComponent
        let ocrEnabled = AppSettings.shared.ocrEnabled
        let filterSecrets = AppSettings.shared.filterSensitiveContent

        // Encrypt + write the full image (AES over multi-MB) and persist off the main thread.
        // The row is inserted only after the file lands, so it never references a missing file.
        Task.detached(priority: .userInitiated) {
            do {
                if try ClipboardItemRepository.recordObservedCopyIfPresent(hash: hash, updatedAt: Date()) != nil {
                    return
                }
            } catch {
                Self.storageLogger.error("observed image copy lookup failed: \(error, privacy: .private)")
                return
            }

            do { try ImageStore.write(data, filename: filename) } catch { return }
            if let thumbData = ImageCache.encodedThumbnail(from: data, maxPixelSize: ImageCache.thumbStorePixelSize) {
                try? ImageStore.write(thumbData, filename: ImageCache.thumbFilename(for: filename))
            }

            let (width, height) = Self.dimensions(from: data)
            let item = ClipboardItemRecord(
                contentHash: hash,
                kind: .image,
                preview: previewName ?? "Image \(width)×\(height)",
                imagePath: filename,
                imageWidth: width,
                imageHeight: height,
                sourceAppBundleId: bundleId,
                sourceAppName: appName,
                sourceAppIconPath: iconPath,
                sourceFilePath: sourcePath,
                byteSize: data.count
            )
            let result: ClipboardItemRepository.ObservedCopyResult
            do {
                result = try ClipboardItemRepository.insertOrRecordObservedCopy(item)
            } catch {
                ImageStore.delete(filename: filename)
                ImageStore.delete(filename: ImageCache.thumbFilename(for: filename))
                Self.storageLogger.error("observed image copy persistence failed: \(error, privacy: .private)")
                return
            }

            guard result.inserted else {
                ImageStore.delete(filename: filename)
                ImageStore.delete(filename: ImageCache.thumbFilename(for: filename))
                return
            }

            await MainActor.run { ClipboardMonitor.shared.notePotentialPrune() }

            if ocrEnabled {
                Task.detached(priority: .utility) {
                    await OCRService.process(itemId: item.id, imagePath: filename, filterSecrets: filterSecrets)
                }
            }
        }
    }

    /// Amortized retention: every Nth insert, prune the DB + orphaned image files off-main.
    private func notePotentialPrune() {
        insertsSincePrune += 1
        guard insertsSincePrune >= Self.pruneEveryNInserts else { return }
        insertsSincePrune = 0
        Task.detached(priority: .utility) { RetentionService.prune() }
    }

    nonisolated private static func dimensions(from data: Data) -> (Int, Int) {
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

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
