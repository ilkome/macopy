import Foundation
import SwiftUI

@Observable
final class RowModel: Identifiable {
    var item: ClipboardItemRecord
    var match: SearchMatch?
    var isSelected: Bool = false

    var id: UUID { item.id }

    private var _parsedURL: URL??
    var parsedURL: URL? {
        if let cached = _parsedURL { return cached }
        let raw = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        var url = URL(string: raw)
        if url == nil,
           let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            url = URL(string: encoded)
        }
        _parsedURL = url
        return url
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
    let snippet: AttributedString
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
