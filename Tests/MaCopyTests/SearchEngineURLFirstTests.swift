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

    // MARK: - preview-enriched fields

    private func makeURLItem(_ url: String, age: TimeInterval = 0) -> ClipboardItemRecord {
        ClipboardItemRecord(
            id: UUID(),
            updatedAt: Date().addingTimeInterval(-age),
            contentHash: url,
            kind: .url,
            text: url,
            preview: String(url.prefix(200))
        )
    }

    private func makePreview(
        forURL url: String,
        title: String? = nil,
        siteName: String? = nil,
        summary: String? = nil,
        hostname: String? = nil
    ) -> LinkPreviewRecord {
        LinkPreviewRecord(
            urlHash: URLNormalizer.hash(url),
            url: url,
            hostname: hostname,
            title: title,
            siteName: siteName,
            summary: summary
        )
    }

    func testTitleMatchEnrichesURLItem() {
        let url = "https://x.example.com/abc"
        let item = makeURLItem(url)
        let preview = makePreview(forURL: url, title: "Krasniqi notes")
        let previews: [String: LinkPreviewRecord] = [preview.urlHash: preview]

        let withoutPreviews = SearchEngine.makeInputs(items: [item], tab: .all)
        let withPreviews = SearchEngine.makeInputs(items: [item], tab: .all, previewsByHash: previews)

        let baseline = SearchEngine.performScoring(inputs: withoutPreviews, query: "krasniqi", urlFirst: false)
        let enriched = SearchEngine.performScoring(inputs: withPreviews, query: "krasniqi", urlFirst: false)

        XCTAssertTrue(baseline.isEmpty, "without preview, URL string alone shouldn't match 'krasniqi'")
        XCTAssertEqual(enriched.count, 1)
        XCTAssertEqual(enriched.first?.id, item.id)
    }

    func testSummaryMatchEnrichesURLItem() {
        let url = "https://x.example.com/zzz"
        let item = makeURLItem(url)
        let preview = makePreview(forURL: url, summary: "deep dive on portmanteau words")
        let previews: [String: LinkPreviewRecord] = [preview.urlHash: preview]

        let inputs = SearchEngine.makeInputs(items: [item], tab: .all, previewsByHash: previews)
        let results = SearchEngine.performScoring(inputs: inputs, query: "portmanteau", urlFirst: false)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, item.id)
    }

    func testHostnameMatchEnrichesURLItem() {
        let url = "https://news.ycombinator.com/item?id=42"
        let item = makeURLItem(url)
        let preview = makePreview(forURL: url, hostname: "news.ycombinator.com")
        let previews: [String: LinkPreviewRecord] = [preview.urlHash: preview]

        let inputs = SearchEngine.makeInputs(items: [item], tab: .all, previewsByHash: previews)
        let results = SearchEngine.performScoring(inputs: inputs, query: "ycombinator", urlFirst: true)
        XCTAssertEqual(results.first?.id, item.id)
    }

    func testPreviewFieldsNotAppliedToNonURLItems() {
        let text = "https://x.example.com/abc"
        let textItem = ClipboardItemRecord(
            id: UUID(),
            contentHash: text,
            kind: .text,
            text: text,
            preview: text
        )
        let preview = makePreview(forURL: text, title: "shouldnotmatch-tokenxyz")
        let previews: [String: LinkPreviewRecord] = [preview.urlHash: preview]

        let inputs = SearchEngine.makeInputs(items: [textItem], tab: .all, previewsByHash: previews)
        let results = SearchEngine.performScoring(inputs: inputs, query: "shouldnotmatch-tokenxyz", urlFirst: false)
        XCTAssertTrue(results.isEmpty, "non-URL kinds must not pull preview fields")
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
