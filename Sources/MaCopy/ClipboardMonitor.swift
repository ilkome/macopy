import AppKit
import CryptoKit
import ImageIO

@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "heic", "webp"]

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
            if imageExts.contains(ext), let data = try? Data(contentsOf: first) {
                return (data, ext)
            }
        }
        return nil
    }

    private func handleText(_ text: String, sourceFile: String?, frontApp: NSRunningApplication?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let kind = ContentTypeDetector.detect(text)
        let hashInput = kind == .url ? Self.normalizeURL(text) : text
        let hash = Self.sha256(Data(hashInput.utf8))

        if let existing = try? ClipboardRepository.findItem(byHash: hash) {
            try? ClipboardRepository.updateUpdatedAt(id: existing.id)
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
        try? ClipboardRepository.insertItem(item)

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

        if let existing = try? ClipboardRepository.findItem(byHash: hash) {
            try? ClipboardRepository.updateUpdatedAt(id: existing.id)
            return
        }

        let filename = "\(UUID().uuidString).\(ext)"
        do { try ImageStore.write(data, filename: filename) } catch { return }

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
        try? ClipboardRepository.insertItem(item)

        if AppSettings.shared.ocrEnabled {
            let id = item.id
            Task.detached(priority: .utility) {
                await OCRService.process(itemId: id, imagePath: filename)
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

    private static func normalizeURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
