import Foundation
import GRDB
import CryptoKit

enum AppDatabaseError: Error, CustomStringConvertible {
    case openFailed(underlying: Error)
    case migrationFailed(underlying: Error)
    case keychainFailed(underlying: Error)

    var description: String {
        switch self {
        case .openFailed(let e): return "Database open failed: \(e)"
        case .migrationFailed(let e): return "Database migration failed: \(e)"
        case .keychainFailed(let e): return "Keychain access failed: \(e)"
        }
    }
}

enum AppDatabase {
    static let databaseFilename = "clipboard.db"

    static var databaseURL: URL {
        Storage.appSupportURL.appendingPathComponent(databaseFilename)
    }

    static let shared: DatabasePool = {
        do {
            return try openSharedDatabase()
        } catch {
            fatalError("AppDatabase init failed: \(error)")
        }
    }()

    private static func openSharedDatabase() throws -> DatabasePool {
        let key: SymmetricKey
        do {
            key = try Keychain.getOrCreateMasterKey()
        } catch {
            throw AppDatabaseError.keychainFailed(underlying: error)
        }
        let keyHex = key.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA key = \"x'\(keyHex)'\"")
            try db.execute(sql: "PRAGMA cipher_memory_security = ON")
        }

        let pool: DatabasePool
        do {
            pool = try DatabasePool(path: databaseURL.path, configuration: config)
        } catch {
            throw AppDatabaseError.openFailed(underlying: error)
        }

        do {
            try migrator.migrate(pool)
        } catch {
            throw AppDatabaseError.migrationFailed(underlying: error)
        }
        return pool
    }

    // Internal (not private) so tests can migrate an in-memory database to the same schema.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "clipboard_items") { t in
                t.column("id", .text).primaryKey()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("contentHash", .text).notNull().unique()
                t.column("kindRaw", .text).notNull()
                t.column("text", .text)
                t.column("preview", .text).notNull().defaults(to: "")
                t.column("imagePath", .text)
                t.column("imageWidth", .integer).notNull().defaults(to: 0)
                t.column("imageHeight", .integer).notNull().defaults(to: 0)
                t.column("ocrText", .text)
                t.column("sourceAppBundleId", .text)
                t.column("sourceAppName", .text)
                t.column("sourceAppIconPath", .text)
                t.column("sourceFilePath", .text)
                t.column("byteSize", .integer).notNull().defaults(to: 0)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("comment", .text)
            }
            try db.create(
                index: "idx_clipboard_items_updatedAt",
                on: "clipboard_items",
                columns: ["updatedAt"]
            )
            try db.create(
                index: "idx_clipboard_items_kindRaw",
                on: "clipboard_items",
                columns: ["kindRaw"]
            )

            try db.create(table: "link_previews") { t in
                t.column("urlHash", .text).primaryKey()
                t.column("url", .text).notNull()
                t.column("hostname", .text)
                t.column("title", .text)
                t.column("siteName", .text)
                t.column("summary", .text)
                t.column("imageData", .blob)
                t.column("iconData", .blob)
                t.column("fetchedAt", .datetime).notNull()
                t.column("statusRaw", .text).notNull()
            }
            try db.create(
                index: "idx_link_previews_hostname",
                on: "link_previews",
                columns: ["hostname"]
            )
        }

        migrator.registerMigration("v2") { db in
            try db.create(table: "folders") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "folder_items") { t in
                t.column("folderId", .text).notNull()
                    .references("folders", onDelete: .cascade)
                t.column("itemId", .text).notNull()
                    .references("clipboard_items", onDelete: .cascade)
                t.column("addedAt", .datetime).notNull()
                t.primaryKey(["folderId", "itemId"])
            }
            try db.create(
                index: "idx_folder_items_itemId",
                on: "folder_items",
                columns: ["itemId"]
            )
        }

        return migrator
    }
}
