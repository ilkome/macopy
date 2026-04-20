import AppKit
import CryptoKit
import SwiftData

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

        if let image = readImage(from: pb) {
            handleImage(image, fileURL: firstFileURL(from: pb), frontApp: frontApp)
            return
        }

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            let text = urls.map { $0.path }.joined(separator: "\n")
            handleText(text, sourceFile: urls.first?.path, frontApp: frontApp)
            return
        }

        if let text = pb.string(forType: .string), !text.isEmpty {
            handleText(text, sourceFile: nil, frontApp: frontApp)
        }
    }

    private func readImage(from pb: NSPasteboard) -> NSImage? {
        if let image = NSImage(pasteboard: pb), image.isValid { return image }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = urls.first,
           imageExts.contains(first.pathExtension.lowercased()),
           let img = NSImage(contentsOf: first) {
            return img
        }
        return nil
    }

    private func firstFileURL(from pb: NSPasteboard) -> URL? {
        (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first
    }

    private func handleText(_ text: String, sourceFile: String?, frontApp: NSRunningApplication?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let hash = Self.sha256(Data(text.utf8))
        let ctx = Storage.container.mainContext

        if let existing = Self.findItem(hash: hash, ctx: ctx) {
            existing.updatedAt = Date()
            try? ctx.save()
            return
        }

        let kind = ContentTypeDetector.detect(text)
        let preview = String(text.prefix(200))
        let iconPath = frontApp.flatMap { IconCache.savedIcon(for: $0) }

        let item = ClipboardItem(
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
        ctx.insert(item)
        try? ctx.save()
    }

    private func handleImage(_ image: NSImage, fileURL: URL?, frontApp: NSRunningApplication?) {
        guard let data = Self.pngData(from: image) else { return }
        let hash = Self.sha256(data)
        let ctx = Storage.container.mainContext

        if let existing = Self.findItem(hash: hash, ctx: ctx) {
            existing.updatedAt = Date()
            try? ctx.save()
            return
        }

        let filename = "\(UUID().uuidString).png"
        let dest = Storage.imageURL(for: filename)
        do { try data.write(to: dest) } catch { return }

        let iconPath = frontApp.flatMap { IconCache.savedIcon(for: $0) }
        let size = image.size
        let preview = fileURL?.lastPathComponent ?? "Image \(Int(size.width))×\(Int(size.height))"

        let item = ClipboardItem(
            contentHash: hash,
            kind: .image,
            preview: preview,
            imagePath: filename,
            imageWidth: Int(size.width),
            imageHeight: Int(size.height),
            sourceAppBundleId: frontApp?.bundleIdentifier,
            sourceAppName: frontApp?.localizedName,
            sourceAppIconPath: iconPath,
            sourceFilePath: fileURL?.path,
            byteSize: data.count
        )
        ctx.insert(item)
        try? ctx.save()

        if AppSettings.shared.ocrEnabled {
            let id = item.id
            Task.detached(priority: .utility) {
                await OCRService.shared.process(itemId: id, imagePath: filename)
            }
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func findItem(hash: String, ctx: ModelContext) -> ClipboardItem? {
        let needle = hash
        let predicate = #Predicate<ClipboardItem> { $0.contentHash == needle }
        var fetch = FetchDescriptor<ClipboardItem>(predicate: predicate)
        fetch.fetchLimit = 1
        return try? ctx.fetch(fetch).first
    }
}
