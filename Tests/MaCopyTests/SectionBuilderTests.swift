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
}
