import XCTest
import GRDB
@testable import MaCopy

/// Exercises FolderRepository against an in-memory database migrated to the same
/// schema as production, injected via FolderRepository.poolOverride (DEBUG only).
final class FolderRepositoryTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try DatabaseQueue()  // in-memory
        try AppDatabase.migrator.migrate(queue)
        FolderRepository.poolOverride = queue
    }

    override func tearDownWithError() throws {
        FolderRepository.poolOverride = nil
        queue = nil
    }

    @discardableResult
    private func insertItem() throws -> UUID {
        let rec = ClipboardItemRecord(contentHash: UUID().uuidString, kind: .text, preview: "x")
        try queue.write { db in try rec.insert(db) }
        return rec.id
    }

    private func itemExists(_ id: UUID) throws -> Bool {
        try queue.read { db in
            try ClipboardItemRecord.filter(ClipboardItemRecord.Columns.id == id).fetchCount(db) > 0
        }
    }

    func testMigrationCreatesFolderTables() throws {
        try queue.read { db in
            XCTAssertTrue(try db.tableExists("folders"))
            XCTAssertTrue(try db.tableExists("folder_items"))
        }
    }

    func testCreateAssignsIncrementingSortIndex() throws {
        let a = try FolderRepository.createFolder(name: "A")
        let b = try FolderRepository.createFolder(name: "B")
        XCTAssertEqual(a.sortIndex, 0)
        XCTAssertEqual(b.sortIndex, 1)
        let all = try FolderRepository.allFolders()
        XCTAssertEqual(all.map(\.name), ["A", "B"])
    }

    func testRenameFolder() throws {
        let f = try FolderRepository.createFolder(name: "Old")
        try FolderRepository.renameFolder(id: f.id, name: "New")
        XCTAssertEqual(try FolderRepository.allFolders().first?.name, "New")
    }

    func testAddMembershipIsIdempotent() throws {
        let f = try FolderRepository.createFolder(name: "F")
        let item = try insertItem()
        try FolderRepository.addMembership(folderId: f.id, itemId: item)
        try FolderRepository.addMembership(folderId: f.id, itemId: item)
        XCTAssertEqual(try FolderRepository.allMemberships().count, 1)
    }

    func testToggleMembership() throws {
        let f = try FolderRepository.createFolder(name: "F")
        let item = try insertItem()
        XCTAssertTrue(try FolderRepository.toggleMembership(folderId: f.id, itemId: item))
        XCTAssertEqual(try FolderRepository.allMemberships().count, 1)
        XCTAssertFalse(try FolderRepository.toggleMembership(folderId: f.id, itemId: item))
        XCTAssertEqual(try FolderRepository.allMemberships().count, 0)
    }

    func testRemoveMembershipOnlyRemovesThatPair() throws {
        let f = try FolderRepository.createFolder(name: "F")
        let g = try FolderRepository.createFolder(name: "G")
        let item = try insertItem()
        try FolderRepository.addMembership(folderId: f.id, itemId: item)
        try FolderRepository.addMembership(folderId: g.id, itemId: item)
        try FolderRepository.removeMembership(folderId: f.id, itemId: item)
        let memberships = try FolderRepository.allMemberships()
        XCTAssertEqual(memberships.count, 1)
        XCTAssertEqual(memberships.first?.folderId, g.id)
    }

    func testDeleteFolderRemovesMembershipsKeepsItems() throws {
        let f = try FolderRepository.createFolder(name: "F")
        let item = try insertItem()
        try FolderRepository.addMembership(folderId: f.id, itemId: item)

        try FolderRepository.deleteFolder(id: f.id)

        XCTAssertTrue(try FolderRepository.allFolders().isEmpty)
        XCTAssertTrue(try FolderRepository.allMemberships().isEmpty)
        XCTAssertTrue(try itemExists(item), "deleting a folder must not delete its items")
    }

    func testDeleteMembershipsForItemAcrossFolders() throws {
        let f = try FolderRepository.createFolder(name: "F")
        let g = try FolderRepository.createFolder(name: "G")
        let item = try insertItem()
        try FolderRepository.addMembership(folderId: f.id, itemId: item)
        try FolderRepository.addMembership(folderId: g.id, itemId: item)

        try FolderRepository.deleteMembershipsForItem(itemId: item)

        XCTAssertTrue(try FolderRepository.allMemberships().isEmpty)
        XCTAssertEqual(try FolderRepository.allFolders().count, 2, "folders must survive")
    }

    func testDeletingItemCascadesMemberships() throws {
        let f = try FolderRepository.createFolder(name: "F")
        let item = try insertItem()
        try FolderRepository.addMembership(folderId: f.id, itemId: item)

        try queue.write { db in
            _ = try ClipboardItemRecord.filter(ClipboardItemRecord.Columns.id == item).deleteAll(db)
        }

        XCTAssertTrue(try FolderRepository.allMemberships().isEmpty, "FK cascade should drop the join row")
    }
}
