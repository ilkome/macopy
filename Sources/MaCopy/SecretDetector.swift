import Foundation

enum SecretKind: String, CaseIterable, Equatable {
    case jwt
    case aws
    case githubClassic = "github_classic"
    case githubFineGrained = "github_fine_grained"
    case stripe
    case openai
    case anthropic
    case google
    case highEntropy = "high_entropy"
}

enum SecretDetector {
    static func redactedSentinel(for kind: SecretKind) -> String {
        String(localized: "[Hidden: \(kind.rawValue)]")
    }

    static func detect(in text: String) -> SecretKind? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for (kind, regex) in compiledPatterns {
            if regex.firstMatch(in: text, options: [], range: full) != nil {
                return kind
            }
        }
        for raw in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            let token = String(raw)
            guard passesEntropyPrefilters(token) else { continue }
            if shannonEntropy(token) >= 4.5 {
                return .highEntropy
            }
        }
        return nil
    }

    static func shannonEntropy(_ s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for c in s { counts[c, default: 0] += 1 }
        let n = Double(s.count)
        var h = 0.0
        for (_, k) in counts {
            let p = Double(k) / n
            h -= p * log2(p)
        }
        return h
    }

    static func passesEntropyPrefilters(_ token: String) -> Bool {
        let len = token.count
        if len < 32 || len > 512 { return false }
        if token.contains(where: { !$0.isASCII }) { return false }
        if token.hasPrefix("/") || token.hasPrefix("~/") { return false }
        if token.contains("://") { return false }
        if token.lowercased().contains("data:") { return false }
        let ns = token as NSString
        let full = NSRange(location: 0, length: ns.length)
        if uuidRegex.firstMatch(in: token, options: [], range: full) != nil { return false }
        let hashLengths: Set<Int> = [32, 40, 56, 64, 96, 128]
        if hashLengths.contains(len), token.allSatisfy({ $0.isHexDigit }) {
            return false
        }
        var classes = 0
        if token.contains(where: { $0.isLowercase }) { classes += 1 }
        if token.contains(where: { $0.isUppercase }) { classes += 1 }
        if token.contains(where: { $0.isNumber }) { classes += 1 }
        if token.contains(where: { "-_+/=".contains($0) }) { classes += 1 }
        if classes < 3 { return false }
        return true
    }

    private static let compiledPatterns: [(SecretKind, NSRegularExpression)] = {
        let raw: [(SecretKind, String)] = [
            (.anthropic, #"\bsk-ant-api03-[A-Za-z0-9_\-]{93}AA\b"#),
            (.openai, #"\b(?:sk-(?:proj|svcacct|admin)-[A-Za-z0-9_\-]{20,}T3BlbkFJ[A-Za-z0-9_\-]{20,}|sk-[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20})\b"#),
            (.githubFineGrained, #"\bgithub_pat_[A-Za-z0-9_]{82}\b"#),
            (.stripe, #"\b(?:sk|rk|pk)_(?:test|live)_[A-Za-z0-9]{24,99}\b"#),
            (.aws, #"\bA(?:KIA|SIA|GPA|ROA|IDA|NPA|NVA|BIA|CCA|3T[A-Z0-9])[A-Z2-7]{16}\b"#),
            (.google, #"\bAIza[A-Za-z0-9_\-]{35}\b"#),
            (.githubClassic, #"\bgh[pousr]_[A-Za-z0-9]{36}\b"#),
            (.jwt, #"\beyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\b"#)
        ]
        return raw.compactMap { kind, pattern in
            (try? NSRegularExpression(pattern: pattern, options: [])).map { (kind, $0) }
        }
    }()

    private static let uuidRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
            options: []
        )
    }()
}
