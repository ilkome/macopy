import XCTest
@testable import MaCopy

final class SearchEngineUsageRankingTests: XCTestCase {
    private func item(
        _ text: String,
        kind: ClipKind = .text,
        updatedAt: Date = Date(),
        copyCount: Int64 = 1,
        pasteCount: Int64 = 0
    ) -> ClipboardItemRecord {
        ClipboardItemRecord(
            updatedAt: updatedAt,
            contentHash: UUID().uuidString,
            kind: kind,
            text: text,
            preview: text,
            copyCount: copyCount,
            pasteCount: pasteCount
        )
    }

    func testUsageBreaksEqualTextualScoreWithinOneTier() {
        let unused = item("identical match", copyCount: 0)
        let used = item("identical match", copyCount: 100, pasteCount: 40)
        let inputs = SearchEngine.makeInputs(items: [unused, used], tab: .all)

        let results = SearchEngine.performScoring(inputs: inputs, query: "identical")

        XCTAssertEqual(results.map(\.id), [used.id, unused.id])
        XCTAssertLessThan(results[0].score, results[1].score)
    }

    func testPasteHasMoreWeightThanCopyFromSameBaseline() {
        let copyBoost = SearchEngine.usageBoost(copyCount: 2, pasteCount: 0)
            - SearchEngine.usageBoost(copyCount: 1, pasteCount: 0)
        let pasteBoost = SearchEngine.usageBoost(copyCount: 1, pasteCount: 1)
            - SearchEngine.usageBoost(copyCount: 1, pasteCount: 0)

        XCTAssertGreaterThan(pasteBoost, copyBoost)
    }

    func testUsageBoostNormalizesNegativeCountsAndCapsAtConfiguredMaximum() {
        XCTAssertEqual(SearchEngine.usageBoost(copyCount: -1, pasteCount: -1), 0)
        XCTAssertEqual(
            SearchEngine.usageBoost(copyCount: .max, pasteCount: .max),
            SearchEngine.usageBoostCap
        )
    }

    func testSubsequenceUsageNeverBeatsFuseTier() throws {
        let fuseItem = item("abcdef", copyCount: 0, pasteCount: 0)
        let subsequenceItem = item(
            "a................b................c................d................e................f",
            copyCount: .max,
            pasteCount: .max
        )
        let inputs = SearchEngine.makeInputs(items: [subsequenceItem, fuseItem], tab: .all)

        let results = SearchEngine.performScoring(inputs: inputs, query: "abcdef")

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, fuseItem.id)
        XCTAssertEqual(results[0].matchingTier, .fuse)
        XCTAssertEqual(results[1].matchingTier, .subsequence)
    }

    func testRawScoreDifferenceAboveCapCannotBeOvercomeWithinTier() {
        let betterUnused = SearchEngine.rankingScore(
            matchScore: 0.1,
            copyCount: 0,
            pasteCount: 0
        )
        let worseMaxed = SearchEngine.rankingScore(
            matchScore: 0.251,
            copyCount: .max,
            pasteCount: .max
        )

        XCTAssertLessThan(betterUnused, worseMaxed)
    }

    func testURLPriorityStillPrecedesTierAndUsage() {
        let text = item("github", copyCount: .max, pasteCount: .max)
        let url = item(
            "https://g-i-t-h-u-b.example",
            kind: .url,
            copyCount: 0,
            pasteCount: 0
        )
        let inputs = SearchEngine.makeInputs(items: [text, url], tab: .all)

        let results = SearchEngine.performScoring(inputs: inputs, query: "github", urlFirst: true)

        XCTAssertEqual(results.first?.id, url.id)
    }
}
