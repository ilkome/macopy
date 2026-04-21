import SwiftUI

enum SearchSnippet {
    static func build(
        text: String,
        ranges: [CountableClosedRange<Int>],
        radius: Int
    ) -> AttributedString {
        let total = text.count
        guard total > 0, let first = ranges.first else {
            return AttributedString(text.replacingOccurrences(of: "\n", with: " "))
        }

        let anchor = first.lowerBound
        let start = max(0, anchor - radius)
        let end = min(total, first.upperBound + 1 + radius)

        let startIdx = text.index(text.startIndex, offsetBy: start)
        let endIdx = text.index(text.startIndex, offsetBy: end)
        let body = text[startIdx..<endIdx].replacingOccurrences(of: "\n", with: " ")

        var attr = AttributedString(body)
        let leadingEllipsis = start > 0
        let trailingEllipsis = end < total
        if leadingEllipsis { attr = AttributedString("…") + attr }
        if trailingEllipsis { attr.append(AttributedString("…")) }

        let prefixOffset = leadingEllipsis ? 1 : 0
        let totalLen = attr.characters.count
        for range in ranges {
            let lo = max(range.lowerBound, start)
            let hi = min(range.upperBound, end - 1)
            guard lo <= hi else { continue }
            let from = lo - start + prefixOffset
            let to = hi - start + prefixOffset + 1
            guard from >= 0, to <= totalLen, from < to else { continue }
            let a = attr.index(attr.startIndex, offsetByCharacters: from)
            let b = attr.index(attr.startIndex, offsetByCharacters: to)
            attr[a..<b].inlinePresentationIntent = .stronglyEmphasized
            attr[a..<b].foregroundColor = .accentColor
        }
        return attr
    }
}
