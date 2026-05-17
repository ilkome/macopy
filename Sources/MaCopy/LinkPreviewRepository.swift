import Foundation
import GRDB

enum LinkPreviewRepository {
    private static var pool: DatabasePool { AppDatabase.shared }

    static func findPreview(byHash hash: String) throws -> LinkPreviewRecord? {
        try pool.read { db in
            try LinkPreviewRecord
                .filter(LinkPreviewRecord.Columns.urlHash == hash)
                .fetchOne(db)
        }
    }

    static func upsertPreview(_ preview: LinkPreviewRecord) throws {
        try pool.write { db in
            try preview.save(db)
        }
    }

    static func deletePreview(urlHash: String) throws {
        _ = try pool.write { db in
            try LinkPreviewRecord
                .filter(LinkPreviewRecord.Columns.urlHash == urlHash)
                .deleteAll(db)
        }
    }

    static func allPreviews() throws -> [LinkPreviewRecord] {
        try pool.read { db in
            try LinkPreviewRecord.fetchAll(db)
        }
    }
}
