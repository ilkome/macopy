import Foundation
import SwiftUI

@Observable
final class RowModel: Identifiable {
    var item: ClipboardItemRecord
    var match: SearchMatch? {
        didSet {
            if match != oldValue { _snippet = nil }
        }
    }
    var isSelected: Bool = false

    var id: UUID { item.id }

    private var _parsedURL: URL??
    var parsedURL: URL? {
        if let cached = _parsedURL { return cached }
        let url = URLNormalizer.parse(item.text ?? item.preview)
        _parsedURL = url
        return url
    }

    // Highlighted snippet is built on first render and cached; scoring keeps only
    // field+ranges so we never allocate AttributedStrings for off-screen matches.
    @ObservationIgnored private var _snippet: AttributedString?
    var snippet: AttributedString? {
        guard let match else { return nil }
        if let cached = _snippet { return cached }
        let built = SearchSnippet.build(text: match.field, ranges: match.ranges, radius: 40)
        _snippet = built
        return built
    }

    init(item: ClipboardItemRecord, match: SearchMatch? = nil) {
        self.item = item
        self.match = match
    }
}

struct RowSection: Identifiable {
    let id: String
    let title: String
    let rows: [RowModel]
}

struct SearchMatch: Equatable {
    let score: Double
    let field: String
    let ranges: [CountableClosedRange<Int>]
}

enum Selectable: Hashable {
    case item(UUID)
    case domain(String)

    var scrollID: String {
        switch self {
        case .item(let id): return id.uuidString
        case .domain(let name): return domainSectionPrefix + name
        }
    }
}
