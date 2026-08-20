import Foundation
import GRDB

enum FolderRepository {
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

    static func allFolders() throws -> [FolderRecord] {
        try pool.read { db in
            try FolderRecord
                .order(FolderRecord.Columns.lastUsedAt.desc, FolderRecord.Columns.sortIndex.desc)
                .fetchAll(db)
        }
    }

    static func allMemberships() throws -> [FolderItemRecord] {
        try pool.read { db in
            try FolderItemRecord.fetchAll(db)
        }
    }

    @discardableResult
    static func createFolder(name: String) throws -> FolderRecord {
        try pool.write { db in
            let nextSort = (try Int.fetchOne(db, sql: "SELECT max(sortIndex) FROM folders") ?? -1) + 1
            let folder = FolderRecord(name: name, sortIndex: nextSort)
            try folder.insert(db)
            return folder
        }
    }

    static func renameFolder(id: UUID, name: String) throws {
        try pool.write { db in
            try FolderRecord
                .filter(FolderRecord.Columns.id == id)
                .updateAll(db, FolderRecord.Columns.name.set(to: name))
        }
    }

    static func recordUse(folderId: UUID, itemId: UUID? = nil, at date: Date = Date()) throws {
        try pool.write { db in
            try FolderRecord
                .filter(FolderRecord.Columns.id == folderId)
                .updateAll(db, FolderRecord.Columns.lastUsedAt.set(to: date))
            if let itemId {
                try FolderItemRecord
                    .filter(FolderItemRecord.Columns.folderId == folderId)
                    .filter(FolderItemRecord.Columns.itemId == itemId)
                    .updateAll(db, FolderItemRecord.Columns.lastUsedAt.set(to: date))
            }
        }
    }

    static func deleteFolder(id: UUID) throws {
        try pool.write { db in
            try FolderItemRecord
                .filter(FolderItemRecord.Columns.folderId == id)
                .deleteAll(db)
            try FolderRecord
                .filter(FolderRecord.Columns.id == id)
                .deleteAll(db)
        }
    }

    static func addMembership(folderId: UUID, itemId: UUID) throws {
        try pool.write { db in
            // Idempotent: the composite PK makes a duplicate add a no-op.
            try FolderItemRecord(folderId: folderId, itemId: itemId).insert(db, onConflict: .ignore)
        }
    }

    static func removeMembership(folderId: UUID, itemId: UUID) throws {
        try pool.write { db in
            try FolderItemRecord
                .filter(FolderItemRecord.Columns.folderId == folderId)
                .filter(FolderItemRecord.Columns.itemId == itemId)
                .deleteAll(db)
        }
    }

    /// Flips membership in a single transaction. Returns the new membership state.
    @discardableResult
    static func toggleMembership(folderId: UUID, itemId: UUID) throws -> Bool {
        try pool.write { db in
            let exists = try FolderItemRecord
                .filter(FolderItemRecord.Columns.folderId == folderId)
                .filter(FolderItemRecord.Columns.itemId == itemId)
                .fetchCount(db) > 0
            if exists {
                try FolderItemRecord
                    .filter(FolderItemRecord.Columns.folderId == folderId)
                    .filter(FolderItemRecord.Columns.itemId == itemId)
                    .deleteAll(db)
                return false
            }
            try FolderItemRecord(folderId: folderId, itemId: itemId).insert(db)
            return true
        }
    }

    static func deleteMembershipsForItem(itemId: UUID) throws {
        try pool.write { db in
            try FolderItemRecord
                .filter(FolderItemRecord.Columns.itemId == itemId)
                .deleteAll(db)
        }
    }

    static func deleteMembershipsForFolder(folderId: UUID) throws {
        try pool.write { db in
            try FolderItemRecord
                .filter(FolderItemRecord.Columns.folderId == folderId)
                .deleteAll(db)
        }
    }
}
