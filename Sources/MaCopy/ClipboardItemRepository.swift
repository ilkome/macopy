import Foundation
import GRDB
import CryptoKit

enum ClipboardItemRepository {
    #if DEBUG
    /// Tests point this at an in-memory writer; production always uses the shared pool.
    nonisolated(unsafe) static var poolOverride: DatabaseWriter?
    #endif

    private static var pool: DatabaseWriter {
        #if DEBUG
        if let poolOverride { return poolOverride }
        #endif
        return AppDatabase.shared
    }

    static func findItem(byHash hash: String) throws -> ClipboardItemRecord? {
        try pool.read { db in
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.contentHash == hash)
                .fetchOne(db)
        }
    }

    static func findItem(byID id: UUID) throws -> ClipboardItemRecord? {
        try pool.read { db in
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.id == id)
                .fetchOne(db)
        }
    }

    static func insertItem(_ item: ClipboardItemRecord) throws {
        try pool.write { db in
            try item.insert(db)
        }
    }

    static func updateUpdatedAt(id: UUID, date: Date = Date()) throws {
        _ = try pool.write { db in
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.id == id)
                .updateAll(db, ClipboardItemRecord.Columns.updatedAt.set(to: date))
        }
    }

    static func updateOCR(id: UUID, text: String) throws {
        _ = try pool.write { db in
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.id == id)
                .updateAll(db, ClipboardItemRecord.Columns.ocrText.set(to: text))
        }
    }

    static func itemsWithOCR() throws -> [ClipboardItemRecord] {
        try pool.read { db in
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.ocrText != nil)
                .fetchAll(db)
        }
    }

    static func batchUpdateOCR(_ pairs: [(UUID, String)]) throws {
        guard !pairs.isEmpty else { return }
        try pool.write { db in
            for (id, text) in pairs {
                try ClipboardItemRecord
                    .filter(ClipboardItemRecord.Columns.id == id)
                    .updateAll(db, ClipboardItemRecord.Columns.ocrText.set(to: text))
            }
        }
    }

    static func updateText(id: UUID, newText: String) throws {
        let newHash = sha256Hex(Data(newText.utf8))
        let newPreview = String(newText.prefix(200))
        let newByteSize = newText.utf8.count
        let now = Date()
        try pool.write { db in
            let target = ClipboardItemRecord.filter(ClipboardItemRecord.Columns.id == id)
            let collision = try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.contentHash == newHash)
                .filter(ClipboardItemRecord.Columns.id != id)
                .fetchCount(db) > 0
            if collision {
                try target.updateAll(
                    db,
                    ClipboardItemRecord.Columns.text.set(to: newText),
                    ClipboardItemRecord.Columns.preview.set(to: newPreview),
                    ClipboardItemRecord.Columns.byteSize.set(to: newByteSize),
                    ClipboardItemRecord.Columns.updatedAt.set(to: now)
                )
            } else {
                try target.updateAll(
                    db,
                    ClipboardItemRecord.Columns.text.set(to: newText),
                    ClipboardItemRecord.Columns.preview.set(to: newPreview),
                    ClipboardItemRecord.Columns.byteSize.set(to: newByteSize),
                    ClipboardItemRecord.Columns.contentHash.set(to: newHash),
                    ClipboardItemRecord.Columns.updatedAt.set(to: now)
                )
            }
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func cloneItem(id: UUID) throws -> UUID? {
        guard let original = try findItem(byID: id), original.kind == .text else { return nil }
        let now = Date()
        let newID = UUID()
        let syntheticHash = sha256Hex(Data((original.contentHash + ":" + newID.uuidString).utf8))
        var clone = original
        clone.id = newID
        clone.createdAt = now
        clone.updatedAt = now
        clone.contentHash = syntheticHash
        try pool.write { db in try clone.insert(db) }
        return newID
    }

    static func updateComment(id: UUID, comment: String?) throws {
        _ = try pool.write { db in
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.id == id)
                .updateAll(db, ClipboardItemRecord.Columns.comment.set(to: comment))
        }
    }

    static func updateFavorite(id: UUID, isFavorite: Bool) throws {
        _ = try pool.write { db in
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.id == id)
                .updateAll(db, ClipboardItemRecord.Columns.isFavorite.set(to: isFavorite))
        }
    }

    static func deleteItem(id: UUID) throws {
        _ = try pool.write { db in
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.id == id)
                .deleteAll(db)
        }
    }

    static func recentItems(limit: Int = 2000) throws -> [ClipboardItemRecord] {
        try pool.read { db in
            try ClipboardItemRecord
                .order(ClipboardItemRecord.Columns.updatedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Newest URL strings for link-preview backfill. Narrow projection (one column, capped
    /// window) instead of fetching every URL row's full record over all history.
    static func recentURLStrings(limit: Int) throws -> [String] {
        try pool.read { db in
            try String.fetchAll(db, sql: """
                SELECT COALESCE(text, preview) FROM clipboard_items
                WHERE kindRaw = 'url'
                ORDER BY updatedAt DESC
                LIMIT ?
                """, arguments: [limit])
        }
    }

    /// Every image file referenced by a row. Used to detect orphaned encrypted files on disk.
    static func allImagePaths() throws -> Set<String> {
        try pool.read { db in
            try String.fetchSet(db, sql: "SELECT imagePath FROM clipboard_items WHERE imagePath IS NOT NULL")
        }
    }

    /// Deletes non-favorite rows that are not in any folder and fall outside the newest `keep`
    /// by updatedAt. Returns the image paths of deleted rows so the caller can remove the
    /// matching encrypted files (and thumbnails) from disk. Favorites and folder members are
    /// preserved regardless of age (a folder-item delete would cascade away the membership).
    @discardableResult
    static func pruneToLimit(keep: Int) throws -> [String] {
        try pool.write { db in
            let predicate = """
                isFavorite = 0
                AND id NOT IN (SELECT itemId FROM folder_items)
                AND id NOT IN (SELECT id FROM clipboard_items ORDER BY updatedAt DESC LIMIT ?)
                """
            let imagePaths = try String.fetchAll(db, sql: """
                SELECT imagePath FROM clipboard_items
                WHERE imagePath IS NOT NULL AND \(predicate)
                """, arguments: [keep])
            try db.execute(sql: "DELETE FROM clipboard_items WHERE \(predicate)", arguments: [keep])
            return imagePaths
        }
    }
}
