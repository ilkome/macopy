import XCTest
@testable import MaCopy

final class SearchEngineURLFirstTests: XCTestCase {

    // MARK: - parseQuery

    func testParseQueryPlain() {
        let p = SearchEngine.parseQuery("hello")
        XCTAssertEqual(p.text, "hello")
        XCTAssertFalse(p.urlFirst)
    }

    func testParseQueryAtPrefix() {
        let p = SearchEngine.parseQuery("@github")
        XCTAssertEqual(p.text, "github")
        XCTAssertTrue(p.urlFirst)
    }

    func testParseQueryAtAlone() {
        let p = SearchEngine.parseQuery("@")
        XCTAssertEqual(p.text, "")
        XCTAssertTrue(p.urlFirst)
    }

    func testParseQueryLeadingWhitespace() {
        let p = SearchEngine.parseQuery("   @ilkome  ")
        XCTAssertEqual(p.text, "ilkome")
        XCTAssertTrue(p.urlFirst)
    }

    func testParseQueryAtWithSpace() {
        let p = SearchEngine.parseQuery("@ ilkome")
        XCTAssertEqual(p.text, "ilkome")
        XCTAssertTrue(p.urlFirst)
    }

    func testParseQueryDoubleAt() {
        let p = SearchEngine.parseQuery("@@x")
        XCTAssertEqual(p.text, "@x")
        XCTAssertTrue(p.urlFirst)
    }

    func testParseQueryEmpty() {
        let p = SearchEngine.parseQuery("")
        XCTAssertEqual(p.text, "")
        XCTAssertFalse(p.urlFirst)
    }

    // MARK: - urlFirst sorting

    private func makeItem(_ text: String, kind: ClipKind, age: TimeInterval = 0) -> ClipboardItemRecord {
        ClipboardItemRecord(
            id: UUID(),
            updatedAt: Date().addingTimeInterval(-age),
            contentHash: text,
            kind: kind,
            text: text,
            preview: String(text.prefix(200))
        )
    }

    func testUrlFirstPushesURLsAbovePlainText() {
        // text item matches "ilkome" much better (exact substring), URL has the same substring
        let textItem = makeItem("ilkome is here", kind: .text)
        let urlItem = makeItem("https://github.com/ilkome", kind: .url)
        let inputs = SearchEngine.makeInputs(items: [textItem, urlItem], tab: .all)

        let withoutUrlFirst = SearchEngine.performScoring(inputs: inputs, query: "ilkome", urlFirst: false)
        let withUrlFirst = SearchEngine.performScoring(inputs: inputs, query: "ilkome", urlFirst: true)

        XCTAssertEqual(withoutUrlFirst.count, 2)
        XCTAssertEqual(withUrlFirst.count, 2)
        XCTAssertEqual(withUrlFirst.first?.kind, .url, "URL should be first when urlFirst is true")
        XCTAssertEqual(withUrlFirst.first?.id, urlItem.id)
    }

    func testUrlFirstKeepsScoreOrderWithinGroup() {
        // two URLs: closer match should come first inside the URL group
        let urlExact = makeItem("https://github.com/ilkome", kind: .url)
        let urlFuzzy = makeItem("https://example.com/ilkme-related", kind: .url)
        let textOther = makeItem("ilkome elsewhere", kind: .text)
        let inputs = SearchEngine.makeInputs(items: [urlFuzzy, textOther, urlExact], tab: .all)

        let results = SearchEngine.performScoring(inputs: inputs, query: "ilkome", urlFirst: true)
        XCTAssertGreaterThanOrEqual(results.count, 2)
        // First two must be URL kind
        XCTAssertEqual(results[0].kind, .url)
        XCTAssertEqual(results[1].kind, .url)
        // exact match should outrank fuzzy match
        XCTAssertEqual(results[0].id, urlExact.id)
    }
}
