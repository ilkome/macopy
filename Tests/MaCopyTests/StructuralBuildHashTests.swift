import XCTest
@testable import MaCopy

final class StructuralBuildHashTests: XCTestCase {
    func testCounterChangeRefreshesReusedRowWithoutChangingStructuralHashInputs() {
        let original = ClipboardItemRecord(
            contentHash: "row",
            kind: .text,
            text: "row",
            preview: "row",
            copyCount: 1,
            pasteCount: 0
        )
        var updated = original
        updated.copyCount = 2

        XCTAssertFalse(ContentView.rowItemUnchanged(original, updated))
        XCTAssertEqual(
            ContentView.structuralBuildHash(
                q: "row",
                urlFirst: false,
                tab: .all,
                rows: [(original.id, original.updatedAt)]
            ),
            ContentView.structuralBuildHash(
                q: "row",
                urlFirst: false,
                tab: .all,
                rows: [(updated.id, updated.updatedAt)]
            )
        )
    }

    private let idA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let idB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_001)

    func testEqualInputsProduceEqualHash() {
        let h1 = ContentView.structuralBuildHash(q: "x", urlFirst: false, tab: .all, rows: [(idA, t1), (idB, t2)])
        let h2 = ContentView.structuralBuildHash(q: "x", urlFirst: false, tab: .all, rows: [(idA, t1), (idB, t2)])
        XCTAssertEqual(h1, h2)
    }

    func testReorderedRowsDiffer() {
        let h1 = ContentView.structuralBuildHash(q: "x", urlFirst: false, tab: .all, rows: [(idA, t1), (idB, t2)])
        let h2 = ContentView.structuralBuildHash(q: "x", urlFirst: false, tab: .all, rows: [(idB, t2), (idA, t1)])
        XCTAssertNotEqual(h1, h2)
    }

    func testDifferentUpdatedAtDiffers() {
        let h1 = ContentView.structuralBuildHash(q: "x", urlFirst: false, tab: .all, rows: [(idA, t1)])
        let h2 = ContentView.structuralBuildHash(q: "x", urlFirst: false, tab: .all, rows: [(idA, t2)])
        XCTAssertNotEqual(h1, h2)
    }

    func testDifferentTabDiffers() {
        let h1 = ContentView.structuralBuildHash(q: "x", urlFirst: false, tab: .all, rows: [(idA, t1)])
        let h2 = ContentView.structuralBuildHash(q: "x", urlFirst: false, tab: .favorites, rows: [(idA, t1)])
        XCTAssertNotEqual(h1, h2)
    }

    func testDifferentQueryDiffers() {
        let h1 = ContentView.structuralBuildHash(q: "abc", urlFirst: false, tab: .all, rows: [(idA, t1)])
        let h2 = ContentView.structuralBuildHash(q: "abd", urlFirst: false, tab: .all, rows: [(idA, t1)])
        XCTAssertNotEqual(h1, h2)
    }

    func testEmptyRowsStillStableWithinRun() {
        let h1 = ContentView.structuralBuildHash(q: "", urlFirst: false, tab: .all, rows: [])
        let h2 = ContentView.structuralBuildHash(q: "", urlFirst: false, tab: .all, rows: [])
        XCTAssertEqual(h1, h2)
    }

    func testAddingRowDiffers() {
        let h1 = ContentView.structuralBuildHash(q: "", urlFirst: false, tab: .all, rows: [(idA, t1)])
        let h2 = ContentView.structuralBuildHash(q: "", urlFirst: false, tab: .all, rows: [(idA, t1), (idB, t2)])
        XCTAssertNotEqual(h1, h2)
    }

    func testUrlFirstFlagDiffers() {
        let h1 = ContentView.structuralBuildHash(q: "x", urlFirst: false, tab: .all, rows: [(idA, t1)])
        let h2 = ContentView.structuralBuildHash(q: "x", urlFirst: true, tab: .all, rows: [(idA, t1)])
        XCTAssertNotEqual(h1, h2)
    }
}
