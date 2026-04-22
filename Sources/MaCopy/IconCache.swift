import AppKit

@MainActor
enum IconCache {
    static func savedIcon(for app: NSRunningApplication) -> String? {
        guard let bundleId = app.bundleIdentifier, let icon = app.icon else { return nil }
        let filename = "\(bundleId).png"
        let url = Storage.iconURL(for: filename)

        if FileManager.default.fileExists(atPath: url.path) {
            return filename
        }

        let size = NSSize(width: 64, height: 64)
        let resized = NSImage(size: size)
        resized.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { return nil }

        try? data.write(to: url)
        return filename
    }
}
