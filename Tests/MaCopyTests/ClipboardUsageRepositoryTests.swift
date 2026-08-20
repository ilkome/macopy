import GRDB
import XCTest
@testable import MaCopy

final class ClipboardUsageRepositoryTests: XCTestCase {
    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        ClipboardItemRepository.poolOverride = queue
    }

    override func tearDownWithError() throws {
        ClipboardItemRepository.poolOverride = nil
        queue = nil
    }

    @discardableResult
    private func insertItem(
        hash: String = UUID().uuidString,
        updatedAt: Date = Date(),
        copyCount: Int64 = 1,
        pasteCount: Int64 = 0
    ) throws -> ClipboardItemRecord {
        let item = ClipboardItemRecord(
            updatedAt: updatedAt,
            contentHash: hash,
            kind: .text,
            text: hash,
            preview: hash,
            copyCount: copyCount,
            pasteCount: pasteCount
        )
        try ClipboardItemRepository.insertItem(item)
        return item
    }

    func testUsageMigrationsBackfillLegacyRows() throws {
        let legacyQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(legacyQueue, upTo: "v2")
        let id = UUID()
        let updatedAt = Date(timeIntervalSince1970: 100)
        try legacyQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clipboard_items
                        (id, createdAt, updatedAt, contentHash, kindRaw, preview)
                    VALUES (?, ?, ?, ?, 'text', 'legacy')
                    """,
                arguments: [id, Date(timeIntervalSince1970: 50), updatedAt, "legacy"]
            )
        }

        try AppDatabase.migrator.migrate(legacyQueue)

        let item = try legacyQueue.read { db in
            try ClipboardItemRecord.fetchOne(db, key: id)
        }
        XCTAssertEqual(item?.copyCount, 1)
        XCTAssertEqual(item?.pasteCount, 0)
        XCTAssertEqual(item?.lastFavoriteUsedAt, updatedAt)
        XCTAssertEqual(item?.lastSiteUsedAt, updatedAt)
    }

    func testCounterConstraintsRejectNegativeValues() throws {
        XCTAssertThrowsError(try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clipboard_items
                        (id, createdAt, updatedAt, contentHash, kindRaw, preview, copyCount, pasteCount)
                    VALUES (?, ?, ?, ?, 'text', 'invalid', -1, 0)
                    """,
                arguments: [UUID(), Date(), Date(), "invalid"]
            )
        })
    }

    func testRecordOperationsIncrementOnlyTheirCounterWithoutTouchingUpdatedAt() throws {
        let date = Date(timeIntervalSince1970: 100)
        let item = try insertItem(updatedAt: date)

        XCTAssertTrue(try ClipboardItemRepository.recordCopy(id: item.id))
        XCTAssertTrue(try ClipboardItemRepository.recordPaste(id: item.id))

        let stored = try XCTUnwrap(ClipboardItemRepository.findItem(byID: item.id))
        XCTAssertEqual(stored.copyCount, 2)
        XCTAssertEqual(stored.pasteCount, 1)
        XCTAssertEqual(stored.updatedAt, date)
    }

    func testSectionUseTimestampsAreIndependent() throws {
        let original = Date(timeIntervalSince1970: 100)
        let favoriteUse = Date(timeIntervalSince1970: 200)
        let siteUse = Date(timeIntervalSince1970: 300)
        let item = try insertItem(updatedAt: original)

        try ClipboardItemRepository.recordFavoriteUse(id: item.id, at: favoriteUse)
        try ClipboardItemRepository.recordSiteUse(id: item.id, at: siteUse)

        let stored = try XCTUnwrap(ClipboardItemRepository.findItem(byID: item.id))
        XCTAssertEqual(stored.lastFavoriteUsedAt, favoriteUse)
        XCTAssertEqual(stored.lastSiteUsedAt, siteUse)
        XCTAssertEqual(stored.updatedAt, original)
    }

    func testEditingDoesNotChangeSectionUseTimestamps() throws {
        let original = Date(timeIntervalSince1970: 100)
        let favoriteUse = Date(timeIntervalSince1970: 200)
        let siteUse = Date(timeIntervalSince1970: 300)
        let item = try insertItem(updatedAt: original)
        try ClipboardItemRepository.recordFavoriteUse(id: item.id, at: favoriteUse)
        try ClipboardItemRepository.recordSiteUse(id: item.id, at: siteUse)

        try ClipboardItemRepository.updateText(id: item.id, newText: "edited")
        try ClipboardItemRepository.updateComment(id: item.id, comment: "comment")

        let stored = try XCTUnwrap(ClipboardItemRepository.findItem(byID: item.id))
        XCTAssertEqual(stored.lastFavoriteUsedAt, favoriteUse)
        XCTAssertEqual(stored.lastSiteUsedAt, siteUse)
    }

    func testCounterOperationsSaturate() throws {
        let item = try insertItem(copyCount: .max, pasteCount: .max)

        try ClipboardItemRepository.recordCopy(id: item.id)
        try ClipboardItemRepository.recordPaste(id: item.id)

        let stored = try XCTUnwrap(ClipboardItemRepository.findItem(byID: item.id))
        XCTAssertEqual(stored.copyCount, .max)
        XCTAssertEqual(stored.pasteCount, .max)
    }

    func testConcurrentCounterRecordingKeepsEveryIncrement() throws {
        let item = try insertItem()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            try! ClipboardItemRepository.recordCopy(id: item.id)
            try! ClipboardItemRepository.recordPaste(id: item.id)
        }

        let stored = try XCTUnwrap(ClipboardItemRepository.findItem(byID: item.id))
        XCTAssertEqual(stored.copyCount, 101)
        XCTAssertEqual(stored.pasteCount, 100)
    }

    func testConcurrentFirstObservationsCreateOneRowAndCountEveryCopy() throws {
        let hash = "shared-hash"
        DispatchQueue.concurrentPerform(iterations: 50) { index in
            let item = ClipboardItemRecord(
                contentHash: hash,
                kind: .text,
                text: "value-\(index)",
                preview: "value"
            )
            _ = try! ClipboardItemRepository.insertOrRecordObservedCopy(item)
        }

        let rows = try queue.read { db in try ClipboardItemRecord.fetchAll(db) }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.copyCount, 50)
        XCTAssertEqual(rows.first?.pasteCount, 0)
    }

    func testObservedDuplicatePreservesContentAndUpdatesTimestamp() throws {
        let originalDate = Date(timeIntervalSince1970: 100)
        let item = try insertItem(hash: "duplicate", updatedAt: originalDate)
        let newDate = Date(timeIntervalSince1970: 200)
        let duplicate = ClipboardItemRecord(
            updatedAt: newDate,
            contentHash: item.contentHash,
            kind: .text,
            text: "replacement",
            preview: "replacement"
        )

        let result = try ClipboardItemRepository.insertOrRecordObservedCopy(duplicate)

        let stored = try XCTUnwrap(ClipboardItemRepository.findItem(byID: item.id))
        XCTAssertFalse(result.inserted)
        XCTAssertEqual(result.id, item.id)
        XCTAssertEqual(stored.text, item.text)
        XCTAssertEqual(stored.copyCount, 2)
        XCTAssertEqual(stored.updatedAt, newDate)
    }

    func testCloneResetsCountersAndEditPreservesThem() throws {
        let original = try insertItem(copyCount: 8, pasteCount: 5)
        let cloneID = try XCTUnwrap(ClipboardItemRepository.cloneItem(id: original.id))
        let clone = try XCTUnwrap(ClipboardItemRepository.findItem(byID: cloneID))
        XCTAssertEqual(clone.copyCount, 0)
        XCTAssertEqual(clone.pasteCount, 0)

        try ClipboardItemRepository.updateText(id: original.id, newText: "edited")
        let edited = try XCTUnwrap(ClipboardItemRepository.findItem(byID: original.id))
        XCTAssertEqual(edited.copyCount, 8)
        XCTAssertEqual(edited.pasteCount, 5)
    }
}
