import Foundation

enum Storage {
    static let appSupportURL: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MaCopy", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.createDirectory(
            at: dir.appendingPathComponent("images"),
            withIntermediateDirectories: true
        )
        try? fm.createDirectory(
            at: dir.appendingPathComponent("icons"),
            withIntermediateDirectories: true
        )
        return dir
    }()

    static func imageURL(for relativePath: String) -> URL {
        appSupportURL.appendingPathComponent("images").appendingPathComponent(relativePath)
    }

    static func iconURL(for relativePath: String) -> URL {
        appSupportURL.appendingPathComponent("icons").appendingPathComponent(relativePath)
    }
}
