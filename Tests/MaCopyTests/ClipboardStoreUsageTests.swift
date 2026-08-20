import GRDB
import XCTest
@testable import MaCopy

@MainActor
final class ClipboardStoreUsageTests: XCTestCase {
    private func waitForVersion(
        _ target: Int,
        in store: ClipboardStore,
        timeout: TimeInterval = 2
    ) async {
        let iterations = Int(timeout / 0.01)
        for _ in 0..<iterations {
            if store.dataVersion >= target { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("dataVersion did not reach \(target)")
    }

    func testProjectionPublishesCountersAndOneVersionPerCounterWrite() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let item = ClipboardItemRecord(
            contentHash: "projection",
            kind: .text,
            text: "projection",
            preview: "projection",
            copyCount: 7,
            pasteCount: 4
        )
        try await queue.write { db in try item.insert(db) }
        ClipboardItemRepository.poolOverride = queue
        defer { ClipboardItemRepository.poolOverride = nil }

        let store = ClipboardStore(databaseWriter: queue)
        await waitForVersion(1, in: store)
        XCTAssertEqual(store.items.first?.copyCount, 7)
        XCTAssertEqual(store.items.first?.pasteCount, 4)
        let baseline = store.dataVersion

        try ClipboardItemRepository.recordPaste(id: item.id)
        await waitForVersion(baseline + 1, in: store)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(store.dataVersion, baseline + 1)
        XCTAssertEqual(store.items.first?.copyCount, 7)
        XCTAssertEqual(store.items.first?.pasteCount, 5)
    }

    func testSingleCounterWriteRefreshesCappedProjectionOnce() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let targetID = UUID()
        try await queue.write { db in
            for index in 0..<2_000 {
                let item = ClipboardItemRecord(
                    id: index == 0 ? targetID : UUID(),
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    contentHash: "item-\(index)",
                    kind: .text,
                    text: "item \(index)",
                    preview: "item \(index)"
                )
                try item.insert(db)
            }
        }
        ClipboardItemRepository.poolOverride = queue
        defer { ClipboardItemRepository.poolOverride = nil }

        let store = ClipboardStore(databaseWriter: queue)
        await waitForVersion(1, in: store)
        XCTAssertEqual(store.items.count, 2_000)
        let baseline = store.dataVersion

        try ClipboardItemRepository.recordCopy(id: targetID)
        await waitForVersion(baseline + 1, in: store)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(store.dataVersion, baseline + 1)
    }
}
