import XCTest
@testable import MaCopy

/// Locks the time-bucketing semantics that #18 reworked from per-row Calendar calls to
/// comparisons against precomputed boundaries.
final class SectionBuilderTests: XCTestCase {
    private func row(updatedAt: Date) -> RowModel {
        RowModel(item: ClipboardItemRecord(
            updatedAt: updatedAt,
            contentHash: UUID().uuidString,
            kind: .text,
            preview: "p"
        ))
    }

    private func row(
        url: String,
        updatedAt: Date,
        favoriteUsedAt: Date? = nil,
        siteUsedAt: Date? = nil
    ) -> RowModel {
        RowModel(item: ClipboardItemRecord(
            updatedAt: updatedAt,
            contentHash: UUID().uuidString,
            kind: .url,
            text: url,
            preview: url,
            isFavorite: true,
            lastFavoriteUsedAt: favoriteUsedAt,
            lastSiteUsedAt: siteUsedAt
        ))
    }

    func testGroupByTimeSeparatesWithinHourFromEarlier() {
        let now = Date()
        let recent = (0..<3).map { _ in row(updatedAt: now) }
        let old = (0..<2).map { _ in row(updatedAt: now.addingTimeInterval(-40 * 86400)) }

        let sections = SectionBuilder.build(recent + old, query: "", tab: .all)

        XCTAssertEqual(sections.map(\.id), ["bucket-0", "bucket-4"])
        XCTAssertEqual(sections.first?.rows.count, 3, "fresh rows land in 'Within the hour'")
        XCTAssertEqual(sections.last?.rows.count, 2, "40-day-old rows land in 'Earlier'")
        XCTAssertEqual(sections.reduce(0) { $0 + $1.rows.count }, 5, "every row placed exactly once")
    }

    func testEmptyListYieldsNoSections() {
        XCTAssertTrue(SectionBuilder.build([], query: "", tab: .all).isEmpty)
    }

    func testFavoritesUseFavoriteTimestampForBucketsAndOrder() throws {
        let now = Date()
        let oldCopy = row(
            url: "https://example.com/old",
            updatedAt: now.addingTimeInterval(-40 * 86400),
            favoriteUsedAt: now
        )
        let newCopy = row(
            url: "https://example.com/new",
            updatedAt: now,
            favoriteUsedAt: now.addingTimeInterval(-60)
        )

        let sections = SectionBuilder.build([newCopy, oldCopy], query: "", tab: .favorites)

        let recent = try XCTUnwrap(sections.first { $0.id == "bucket-0" })
        XCTAssertEqual(recent.rows.map(\.id), [oldCopy.id, newCopy.id])
        XCTAssertFalse(sections.contains { $0.id == "bucket-4" })
    }

    func testSitesAndTheirItemsUseSiteTimestampOrder() {
        let base = Date(timeIntervalSince1970: 1_000)
        let olderA = row(url: "https://a.test/old", updatedAt: base, siteUsedAt: base)
        let recentA = row(
            url: "https://a.test/recent",
            updatedAt: base.addingTimeInterval(1),
            siteUsedAt: base.addingTimeInterval(30)
        )
        let firstB = row(
            url: "https://b.test/one",
            updatedAt: base.addingTimeInterval(20),
            siteUsedAt: base.addingTimeInterval(10)
        )
        let secondB = row(
            url: "https://b.test/two",
            updatedAt: base.addingTimeInterval(21),
            siteUsedAt: base.addingTimeInterval(11)
        )

        let sections = SectionBuilder.build(
            [olderA, firstB, recentA, secondB],
            query: "",
            tab: .urls
        )

        XCTAssertEqual(sections.map(\.id), ["domain-a.test", "domain-b.test"])
        XCTAssertEqual(sections.first?.rows.map(\.id), [recentA.id, olderA.id])
    }

    func testQuickPasteNumbersContinueAcrossTimeSections() {
        let first = UUID()
        let second = UUID()
        let visible: [Selectable] = [.item(first), .item(second)]

        let assignments = SelectionHelpers.quickPasteAssignments(visible: visible)

        XCTAssertEqual(assignments[first], 1)
        XCTAssertEqual(assignments[second], 2)
    }

    func testQuickPasteNumbersRefreshAfterTabChange() {
        let firstTabRows = [row(updatedAt: Date()), row(updatedAt: Date())]
        let secondTabRows = [row(updatedAt: Date()), row(updatedAt: Date())]
        let allRows = firstTabRows + secondTabRows
        let rowsById = Dictionary(uniqueKeysWithValues: allRows.map { ($0.id, $0) })

        SelectionHelpers.applyQuickPasteNumbers(
            rowsById: rowsById,
            visible: firstTabRows.map { .item($0.id) },
            commandHeld: true
        )
        SelectionHelpers.applyQuickPasteNumbers(
            rowsById: rowsById,
            visible: firstTabRows.map { .item($0.id) },
            commandHeld: false
        )
        SelectionHelpers.applyQuickPasteNumbers(
            rowsById: rowsById,
            visible: secondTabRows.map { .item($0.id) },
            commandHeld: true
        )

        XCTAssertNil(firstTabRows[0].quickPasteNumber)
        XCTAssertEqual(secondTabRows[0].quickPasteNumber, 1)
        XCTAssertEqual(secondTabRows[1].quickPasteNumber, 2)
    }
}
