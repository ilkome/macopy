import XCTest
import GRDB
@testable import MaCopy

/// Exercises retention SQL against an in-memory database. The dangerous failure mode is pruning
/// rows the user expects to keep (favorites, folder members), so those are asserted explicitly.
final class RetentionTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try DatabaseQueue()  // in-memory
        try AppDatabase.migrator.migrate(queue)
        ClipboardItemRepository.poolOverride = queue
        FolderRepository.poolOverride = queue
        LinkPreviewRepository.poolOverride = queue
    }

    override func tearDownWithError() throws {
        ClipboardItemRepository.poolOverride = nil
        FolderRepository.poolOverride = nil
        LinkPreviewRepository.poolOverride = nil
        queue = nil
    }

    @discardableResult
    private func insert(daysAgo: Int, favorite: Bool = false, imagePath: String? = nil) throws -> UUID {
        let rec = ClipboardItemRecord(
            updatedAt: Date().addingTimeInterval(-Double(daysAgo) * 86400),
            contentHash: UUID().uuidString,
            kind: imagePath == nil ? .text : .image,
            preview: "p",
            imagePath: imagePath,
            isFavorite: favorite
        )
        try queue.write { db in try rec.insert(db) }
        return rec.id
    }

    private func exists(_ id: UUID) throws -> Bool {
        try queue.read { db in
            try ClipboardItemRecord.filter(ClipboardItemRecord.Columns.id == id).fetchCount(db) > 0
        }
    }

    func testKeepsNewestAndPrunesOverflow() throws {
        let ids = try (0..<5).map { try insert(daysAgo: $0) }  // index 0 = newest
        try ClipboardItemRepository.pruneToLimit(keep: 3)
        XCTAssertTrue(try exists(ids[0]))
        XCTAssertTrue(try exists(ids[1]))
        XCTAssertTrue(try exists(ids[2]))
        XCTAssertFalse(try exists(ids[3]))
        XCTAssertFalse(try exists(ids[4]))
    }

    func testFavoriteSurvivesBeyondLimit() throws {
        let fav = try insert(daysAgo: 100, favorite: true)
        for day in 0..<3 { try insert(daysAgo: day) }
        try ClipboardItemRepository.pruneToLimit(keep: 2)
        XCTAssertTrue(try exists(fav), "favorites must survive retention")
    }

    func testFolderMemberSurvivesBeyondLimit() throws {
        let member = try insert(daysAgo: 100)
        let folder = try FolderRepository.createFolder(name: "F")
        try FolderRepository.addMembership(folderId: folder.id, itemId: member)
        for day in 0..<3 { try insert(daysAgo: day) }
        try ClipboardItemRepository.pruneToLimit(keep: 2)
        XCTAssertTrue(try exists(member), "folder members must survive retention")
    }

    func testReturnsPrunedImagePaths() throws {
        try insert(daysAgo: 0)  // newest text row, survives
        let oldImage = try insert(daysAgo: 50, imagePath: "old.png")
        let removed = try ClipboardItemRepository.pruneToLimit(keep: 1)
        XCTAssertEqual(removed, ["old.png"])
        XCTAssertFalse(try exists(oldImage))
    }

    func testPrunesPreviewsByAge() throws {
        try LinkPreviewRepository.upsertPreview(
            LinkPreviewRecord(urlHash: "fresh", url: "https://a", fetchedAt: Date()))
        try LinkPreviewRepository.upsertPreview(
            LinkPreviewRecord(urlHash: "old", url: "https://b",
                              fetchedAt: Date().addingTimeInterval(-100 * 86400)))
        try LinkPreviewRepository.pruneOlderThan(30 * 86400)
        XCTAssertEqual(try LinkPreviewRepository.existingHashes(), ["fresh"])
    }
}
