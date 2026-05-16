import AppKit

@MainActor
enum IconCache {
    static func savedIcon(for app: NSRunningApplication) -> String? {
        guard let bundleId = app.bundleIdentifier, let icon = app.icon else { return nil }
        let safeBundleId = sanitize(bundleId)
        guard !safeBundleId.isEmpty else { return nil }
        let filename = "\(safeBundleId).png"
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

    static func sanitize(_ bundleId: String) -> String {
        let mapped = bundleId.unicodeScalars.map { scalar -> Character in
            let v = scalar.value
            let isAlnum = (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A)
            let isDotOrDash = scalar == "." || scalar == "-"
            return (isAlnum || isDotOrDash) ? Character(scalar) : "_"
        }
        return String(mapped.prefix(200))
    }
}
