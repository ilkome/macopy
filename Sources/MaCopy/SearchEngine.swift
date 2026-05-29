import Foundation
import Fuse

enum SearchEngine {
    struct ParsedQuery: Equatable, Sendable {
        let text: String
        let urlFirst: Bool
    }

    struct ScoringInput: Sendable {
        let id: UUID
        let updatedAt: Date
        let kind: ClipKind
        let fields: [String]
    }

    struct ScoredResult: Sendable {
        let id: UUID
        let kind: ClipKind
        let score: Double
        let snippet: AttributedString
    }

    static func parseQuery(_ raw: String) -> ParsedQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("@") else {
            return ParsedQuery(text: trimmed, urlFirst: false)
        }
        let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedQuery(text: rest, urlFirst: true)
    }

    static func makeInputs(
        items: [ClipboardItemRecord],
        tab: Tab,
        previewsByHash: [String: LinkPreviewRecord] = [:]
    ) -> [ScoringInput] {
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
                if item.kind == .url, !previewsByHash.isEmpty {
                    let raw = item.text ?? item.preview
                    let hash = URLNormalizer.hash(raw)
                    if let preview = previewsByHash[hash] {
                        if let s = preview.title, !s.isEmpty { fields.append(s) }
                        if let s = preview.siteName, !s.isEmpty { fields.append(s) }
                        if let s = preview.summary, !s.isEmpty {
                            fields.append(s.count > 500 ? String(s.prefix(500)) : s)
                        }
                        if let s = preview.hostname, !s.isEmpty { fields.append(s) }
                    }
                }
                return ScoringInput(id: item.id, updatedAt: item.updatedAt, kind: item.kind, fields: fields)
            }
    }

    static func performScoring(
        inputs: [ScoringInput],
        query: String,
        urlFirst: Bool = false
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
            if urlFirst {
                let l = lhs.0.kind == .url
                let r = rhs.0.kind == .url
                if l != r { return l && !r }
            }
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.0.updatedAt != rhs.0.updatedAt { return lhs.0.updatedAt > rhs.0.updatedAt }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }
        return scored.map { input, score, field, ranges in
            let snippet = SearchSnippet.build(text: field, ranges: ranges, radius: 40)
            return ScoredResult(id: input.id, kind: input.kind, score: score, snippet: snippet)
        }
    }

    static func structuralBuildHash(
        q: String,
        urlFirst: Bool,
        tab: Tab,
        rows: [(UUID, Date)]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(q)
        hasher.combine(urlFirst)
        hasher.combine(tab.rawValue)
        for (id, updatedAt) in rows {
            hasher.combine(id)
            hasher.combine(updatedAt)
        }
        return hasher.finalize()
    }
}
