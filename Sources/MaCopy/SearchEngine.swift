import Foundation
import Fuse

enum SearchEngine {
    struct ScoringInput: Sendable {
        let id: UUID
        let updatedAt: Date
        let fields: [String]
    }

    struct ScoredResult: Sendable {
        let id: UUID
        let score: Double
        let snippet: AttributedString
    }

    static func makeInputs(items: [ClipboardItemRecord], tab: Tab) -> [ScoringInput] {
        items
            .filter { tab.matches($0) }
            .map { item in
                var fields: [String] = []
                if let s = item.text, !s.isEmpty {
                    fields.append(s)
                } else if !item.preview.isEmpty {
                    fields.append(item.preview)
                }
                if let s = item.ocrText, !s.isEmpty {
                    fields.append(s.count > 500 ? String(s.prefix(500)) : s)
                }
                if let s = item.comment, !s.isEmpty { fields.append(s) }
                return ScoringInput(id: item.id, updatedAt: item.updatedAt, fields: fields)
            }
    }

    static func performScoring(
        inputs: [ScoringInput],
        query: String
    ) -> [ScoredResult] {
        let fuse = Fuse(location: 0, distance: 1_000_000, threshold: 0.4)
        guard let pattern = fuse.createPattern(from: query) else { return [] }
        var scored: [(ScoringInput, Double, String, [CountableClosedRange<Int>])] = []
        scored.reserveCapacity(inputs.count)
        for input in inputs {
            if Task.isCancelled { return [] }
            var bestScore: Double?
            var bestField: String?
            var bestRanges: [CountableClosedRange<Int>] = []
            for field in input.fields {
                guard let r = fuse.search(pattern, in: field) else { continue }
                if bestScore == nil || r.score < bestScore! {
                    bestScore = r.score
                    bestField = field
                    bestRanges = r.ranges
                }
            }
            if bestScore == nil {
                for field in input.fields {
                    guard let r = SubsequenceSearch.search(pattern: query, in: field) else { continue }
                    if bestScore == nil || r.score < bestScore! {
                        bestScore = r.score
                        bestField = field
                        bestRanges = r.ranges
                    }
                }
            }
            if let s = bestScore, let field = bestField, !bestRanges.isEmpty {
                scored.append((input, s, field, bestRanges))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.0.updatedAt != rhs.0.updatedAt { return lhs.0.updatedAt > rhs.0.updatedAt }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }
        return scored.map { input, score, field, ranges in
            let snippet = SearchSnippet.build(text: field, ranges: ranges, radius: 40)
            return ScoredResult(id: input.id, score: score, snippet: snippet)
        }
    }

    static func structuralBuildHash(
        q: String,
        tab: Tab,
        rows: [(UUID, Date)]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(q)
        hasher.combine(tab.rawValue)
        for (id, updatedAt) in rows {
            hasher.combine(id)
            hasher.combine(updatedAt)
        }
        return hasher.finalize()
    }
}
