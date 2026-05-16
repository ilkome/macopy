import AppKit
import Foundation
import SwiftData

// Mirrors the SwiftData schema that shipped in v0.0.6 so we can read the old
// `clipboard.store` file. These types are private to migration and intentionally
// disconnected from the rest of the app.
@Model
fileprivate final class ClipboardItem {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var contentHash: String
    var kindRaw: String
    var text: String?
    var preview: String
    var imagePath: String?
    var imageWidth: Int
    var imageHeight: Int
    var ocrText: String?
    var sourceAppBundleId: String?
    var sourceAppName: String?
    var sourceAppIconPath: String?
    var sourceFilePath: String?
    var byteSize: Int
    var isFavorite: Bool = false
    var comment: String?

    init() {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.contentHash = ""
        self.kindRaw = "text"
        self.preview = ""
        self.imageWidth = 0
        self.imageHeight = 0
        self.byteSize = 0
    }
}

@Model
fileprivate final class LinkPreview {
    @Attribute(.unique) var urlHash: String
    var url: String
    var hostname: String?
    var title: String?
    var siteName: String?
    var summary: String?
    var imageData: Data?
    var iconData: Data?
    var fetchedAt: Date
    var statusRaw: String

    init() {
        self.urlHash = ""
        self.url = ""
        self.fetchedAt = Date()
        self.statusRaw = "pending"
    }
}

@MainActor
enum LegacyMigrator {
    private static let completedFlagKey = "sqlCipherMigrationCompleted_v1"
    private static let lockFilename = "migration.lock"
    private static let legacyDBFilename = "clipboard.store"
    private static let backupSuffix = ".pre-encryption.bak"
    private static let legacyImagesFolder = "images"
    private static let legacyImagesBackupFolder = "images.pre-encryption.bak"
    private static let batchSize = 500

    static func runIfNeeded() {
        if UserDefaults.standard.bool(forKey: completedFlagKey) {
            return
        }
        let fm = FileManager.default
        let appSupport = Storage.appSupportURL
        let legacyDB = appSupport.appendingPathComponent(legacyDBFilename)

        guard fm.fileExists(atPath: legacyDB.path) else {
            UserDefaults.standard.set(true, forKey: completedFlagKey)
            return
        }

        if hasIncompleteMigration(appSupport: appSupport) {
            cleanupAfterCrash(appSupport: appSupport)
        }

        guard showStartAlert() else {
            NSLog("LegacyMigrator: user declined migration; exiting")
            NSApp.terminate(nil)
            return
        }

        do {
            try performMigration(appSupport: appSupport)
            UserDefaults.standard.set(true, forKey: completedFlagKey)
            showCompletionAlert(success: true, error: nil)
        } catch {
            NSLog("LegacyMigrator: migration failed: \(error)")
            showCompletionAlert(success: false, error: error)
            NSApp.terminate(nil)
        }
    }

    private static func hasIncompleteMigration(appSupport: URL) -> Bool {
        let fm = FileManager.default
        let lock = appSupport.appendingPathComponent(lockFilename)
        let newDB = appSupport.appendingPathComponent(AppDatabase.databaseFilename)
        return fm.fileExists(atPath: lock.path) || fm.fileExists(atPath: newDB.path)
    }

    private static func cleanupAfterCrash(appSupport: URL) {
        NSLog("LegacyMigrator: cleaning up incomplete previous migration")
        let fm = FileManager.default
        let newDB = appSupport.appendingPathComponent(AppDatabase.databaseFilename)
        for suffix in ["", "-shm", "-wal"] {
            let url = newDB.appendingPathExtension(suffix.isEmpty ? "" : String(suffix.dropFirst()))
            let actualURL = suffix.isEmpty ? newDB : URL(fileURLWithPath: newDB.path + suffix)
            _ = try? fm.removeItem(at: actualURL)
            _ = url
        }
        let imagesDir = appSupport.appendingPathComponent(legacyImagesFolder)
        if let entries = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) {
            for entry in entries where entry.pathExtension == "enc" {
                try? fm.removeItem(at: entry)
            }
        }
        let lock = appSupport.appendingPathComponent(lockFilename)
        try? fm.removeItem(at: lock)
    }

    private static func performMigration(appSupport: URL) throws {
        let fm = FileManager.default
        let lock = appSupport.appendingPathComponent(lockFilename)
        fm.createFile(atPath: lock.path, contents: Data())

        defer { try? fm.removeItem(at: lock) }

        try backupLegacyStore(appSupport: appSupport, fm: fm)
        try backupImages(appSupport: appSupport, fm: fm)

        let legacyContainer = try makeLegacyContainer(appSupport: appSupport)
        let legacyContext = ModelContext(legacyContainer)

        _ = AppDatabase.shared

        try copyClipboardItems(from: legacyContext)
        try copyLinkPreviews(from: legacyContext)
        try reencryptImages(appSupport: appSupport, fm: fm)
    }

    private static func makeLegacyContainer(appSupport: URL) throws -> ModelContainer {
        let schema = Schema([ClipboardItem.self, LinkPreview.self])
        let url = appSupport.appendingPathComponent(legacyDBFilename)
        let config = ModelConfiguration(url: url)
        return try ModelContainer(for: schema, configurations: config)
    }

    private static func copyClipboardItems(from ctx: ModelContext) throws {
        var offset = 0
        var migrated = 0
        var skipped = 0
        while true {
            var fetch = FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
            )
            fetch.fetchLimit = batchSize
            fetch.fetchOffset = offset
            let batch = try ctx.fetch(fetch)
            if batch.isEmpty { break }
            for legacy in batch {
                let kind = ClipKind(rawValue: legacy.kindRaw) ?? .text
                let record = ClipboardItemRecord(
                    id: legacy.id,
                    createdAt: legacy.createdAt,
                    updatedAt: legacy.updatedAt,
                    contentHash: legacy.contentHash,
                    kind: kind,
                    text: legacy.text,
                    preview: legacy.preview,
                    imagePath: legacy.imagePath,
                    imageWidth: legacy.imageWidth,
                    imageHeight: legacy.imageHeight,
                    ocrText: legacy.ocrText,
                    sourceAppBundleId: legacy.sourceAppBundleId,
                    sourceAppName: legacy.sourceAppName,
                    sourceAppIconPath: legacy.sourceAppIconPath,
                    sourceFilePath: legacy.sourceFilePath,
                    byteSize: legacy.byteSize,
                    isFavorite: legacy.isFavorite,
                    comment: legacy.comment
                )
                do {
                    try ClipboardRepository.insertItem(record)
                    migrated += 1
                } catch {
                    skipped += 1
                }
            }
            offset += batch.count
        }
        NSLog("LegacyMigrator: clipboard items — migrated \(migrated), skipped \(skipped)")
    }

    private static func copyLinkPreviews(from ctx: ModelContext) throws {
        var offset = 0
        var migrated = 0
        var skipped = 0
        while true {
            var fetch = FetchDescriptor<LinkPreview>()
            fetch.fetchLimit = batchSize
            fetch.fetchOffset = offset
            let batch = try ctx.fetch(fetch)
            if batch.isEmpty { break }
            for legacy in batch {
                let status = LinkPreviewStatus(rawValue: legacy.statusRaw) ?? .pending
                let record = LinkPreviewRecord(
                    urlHash: legacy.urlHash,
                    url: legacy.url,
                    hostname: legacy.hostname,
                    title: legacy.title,
                    siteName: legacy.siteName,
                    summary: legacy.summary,
                    imageData: legacy.imageData,
                    iconData: legacy.iconData,
                    fetchedAt: legacy.fetchedAt,
                    status: status
                )
                do {
                    try ClipboardRepository.upsertPreview(record)
                    migrated += 1
                } catch {
                    skipped += 1
                }
            }
            offset += batch.count
        }
        NSLog("LegacyMigrator: link previews — migrated \(migrated), skipped \(skipped)")
    }

    private static func reencryptImages(appSupport: URL, fm: FileManager) throws {
        let imagesDir = appSupport.appendingPathComponent(legacyImagesFolder)
        guard let entries = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) else {
            return
        }
        for entry in entries {
            if entry.pathExtension == "enc" { continue }
            let filename = entry.lastPathComponent
            guard let data = try? Data(contentsOf: entry) else { continue }
            do {
                try ImageStore.write(data, filename: filename)
                try fm.removeItem(at: entry)
            } catch {
                NSLog("LegacyMigrator: failed to encrypt \(filename): \(error)")
                throw error
            }
        }
    }

    private static func backupLegacyStore(appSupport: URL, fm: FileManager) throws {
        for suffix in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: appSupport.appendingPathComponent(legacyDBFilename).path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = URL(fileURLWithPath: src.path + backupSuffix)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
        }
    }

    private static func backupImages(appSupport: URL, fm: FileManager) throws {
        let src = appSupport.appendingPathComponent(legacyImagesFolder)
        guard fm.fileExists(atPath: src.path) else { return }
        let dst = appSupport.appendingPathComponent(legacyImagesBackupFolder)
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
    }

    @discardableResult
    private static func showStartAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Обновление до версии с шифрованием"
        alert.informativeText = """
        MaCopy теперь шифрует историю на диске. Сейчас существующая база будет переведена в зашифрованный формат — это займёт несколько секунд.

        На всякий случай рядом будет сохранена незашифрованная резервная копия (clipboard.store.pre-encryption.bak). После того как ты убедишься, что всё работает, её можно удалить.
        """
        alert.addButton(withTitle: "Продолжить")
        alert.addButton(withTitle: "Выйти")
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    private static func showCompletionAlert(success: Bool, error: Error?) {
        let alert = NSAlert()
        if success {
            alert.messageText = "База зашифрована"
            alert.informativeText = "Резервная копия лежит в ~/Library/Application Support/MaCopy/. Удали её, когда убедишься, что приложение работает корректно."
        } else {
            alert.alertStyle = .critical
            alert.messageText = "Не удалось зашифровать базу"
            alert.informativeText = """
            \(error.map { String(describing: $0) } ?? "Неизвестная ошибка")

            Резервная копия сохранена. Можно вернуться на старую версию (v0.0.6) и продолжить пользоваться без шифрования.
            """
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
