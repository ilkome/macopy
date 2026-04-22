import Foundation
import SwiftData

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

    @MainActor
    static let container: ModelContainer = {
        let schema = Schema([ClipboardItem.self])
        let url = appSupportURL.appendingPathComponent("clipboard.store")
        let config = ModelConfiguration(url: url)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }()
}
