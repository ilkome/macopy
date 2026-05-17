import Foundation
import GRDB

enum ClipboardItemRepository {
    private static var pool: DatabasePool { AppDatabase.shared }

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
        try pool.write { db in
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.id == id)
                .updateAll(db, ClipboardItemRecord.Columns.updatedAt.set(to: date))
        }
    }

    static func updateOCR(id: UUID, text: String) throws {
        try pool.write { db in
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

    static func updateComment(id: UUID, comment: String?) throws {
        try pool.write { db in
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.id == id)
                .updateAll(db, ClipboardItemRecord.Columns.comment.set(to: comment))
        }
    }

    static func updateFavorite(id: UUID, isFavorite: Bool) throws {
        try pool.write { db in
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

    static func urlItems() throws -> [ClipboardItemRecord] {
        try pool.read { db in
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.kindRaw == "url")
                .fetchAll(db)
        }
    }
}
