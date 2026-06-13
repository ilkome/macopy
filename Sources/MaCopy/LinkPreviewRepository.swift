import Foundation
import GRDB

enum LinkPreviewRepository {
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

    /// urlHashes of all stored previews. One narrow column instead of full records - lets the
    /// backfill diff "which URLs already have a preview" in memory without an N+1 of point reads.
    static func existingHashes() throws -> Set<String> {
        try pool.read { db in
            try String.fetchSet(db, sql: "SELECT urlHash FROM link_previews")
        }
    }

    /// One favicon blob for a hostname (any matching preview that has one). Backs FaviconCache
    /// so domain rows don't keep every icon resident in memory.
    static func iconData(forHostname hostname: String) throws -> Data? {
        try pool.read { db in
            try Data.fetchOne(db, sql: """
                SELECT iconData FROM link_previews
                WHERE hostname = ? AND iconData IS NOT NULL
                LIMIT 1
                """, arguments: [hostname])
        }
    }

    static func pruneOlderThan(_ maxAge: TimeInterval) throws {
        let cutoff = Date().addingTimeInterval(-maxAge)
        _ = try pool.write { db in
            try LinkPreviewRecord
                .filter(LinkPreviewRecord.Columns.fetchedAt < cutoff)
                .deleteAll(db)
        }
    }
}
