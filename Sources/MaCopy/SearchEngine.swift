import Foundation
import Fuse

enum SearchEngine {
    enum MatchingTier: Int, Sendable {
        case fuse
        case subsequence
    }

    struct ParsedQuery: Equatable, Sendable {
        let text: String
        let urlFirst: Bool
    }

    struct ScoringInput: Sendable {
        let id: UUID
        let updatedAt: Date
        let kind: ClipKind
        let fields: [String]
        let copyCount: Int64
        let pasteCount: Int64
    }

    struct ScoredResult: Sendable {
        let id: UUID
        let kind: ClipKind
        let score: Double
        let matchingTier: MatchingTier
        // Snippet stays as field text + match ranges; the AttributedString is built
        // lazily per visible row (see RowModel.snippet), not eagerly for every result.
        let field: String
        let ranges: [CountableClosedRange<Int>]
    }

    // Top-N results by score are kept; nobody scrolls past a few hundred matches,
    // and the tail only burns reconcile/section-build work.
    static let resultCap = 300
    static let copyWeight = 1.0
    static let pasteWeight = 2.0
    static let usageScale = 0.03
    static let usageBoostCap = 0.15

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
                return ScoringInput(
                    id: item.id,
                    updatedAt: item.updatedAt,
                    kind: item.kind,
                    fields: fields,
                    copyCount: item.copyCount,
                    pasteCount: item.pasteCount
                )
            }
    }

    static func usageBoost(copyCount: Int64, pasteCount: Int64) -> Double {
        let safeCopyCount = Double(max(0, copyCount))
        let safePasteCount = Double(max(0, pasteCount))
        let usage = copyWeight * log1p(safeCopyCount)
            + pasteWeight * log1p(safePasteCount)
        return min(usageBoostCap, usage * usageScale)
    }

    static func rankingScore(
        matchScore: Double,
        copyCount: Int64,
        pasteCount: Int64
    ) -> Double {
        matchScore - usageBoost(copyCount: copyCount, pasteCount: pasteCount)
    }

    static func performScoring(
        inputs: [ScoringInput],
        query: String,
        urlFirst: Bool = false
    ) -> [ScoredResult] {
        let fuse = Fuse(location: 0, distance: 1_000_000, threshold: 0.4)
        guard let pattern = fuse.createPattern(from: query) else { return [] }
        var scored: [(
            input: ScoringInput,
            tier: MatchingTier,
            rankingScore: Double,
            field: String,
            ranges: [CountableClosedRange<Int>]
        )] = []
        scored.reserveCapacity(inputs.count)
        for input in inputs {
            if Task.isCancelled { return [] }
            var bestScore: Double?
            var bestField: String?
            var bestRanges: [CountableClosedRange<Int>] = []
            var matchingTier: MatchingTier = .fuse
            for field in input.fields {
                guard let r = fuse.search(pattern, in: field) else { continue }
                if bestScore == nil || r.score < bestScore! {
                    bestScore = r.score
                    bestField = field
                    bestRanges = r.ranges
                }
            }
            if bestScore == nil {
                matchingTier = .subsequence
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
                let rankingScore = rankingScore(
                    matchScore: s,
                    copyCount: input.copyCount,
                    pasteCount: input.pasteCount
                )
                scored.append((input, matchingTier, rankingScore, field, bestRanges))
            }
        }
        scored.sort { lhs, rhs in
            if urlFirst {
                let l = lhs.input.kind == .url
                let r = rhs.input.kind == .url
                if l != r { return l && !r }
            }
            if lhs.tier != rhs.tier { return lhs.tier.rawValue < rhs.tier.rawValue }
            if lhs.rankingScore != rhs.rankingScore { return lhs.rankingScore < rhs.rankingScore }
            if lhs.input.updatedAt != rhs.input.updatedAt {
                return lhs.input.updatedAt > rhs.input.updatedAt
            }
            return lhs.input.id.uuidString < rhs.input.id.uuidString
        }
        return scored.prefix(resultCap).map { candidate in
            ScoredResult(
                id: candidate.input.id,
                kind: candidate.input.kind,
                score: candidate.rankingScore,
                matchingTier: candidate.tier,
                field: candidate.field,
                ranges: candidate.ranges
            )
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
