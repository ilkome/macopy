import Foundation

enum ContentTypeDetector {
    static func detect(_ raw: String) -> ClipKind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isURL(text) { return .url }
        if isColor(text) { return .color }
        if isCode(raw) { return .code }
        return .text
    }

    private static func isURL(_ s: String) -> Bool {
        guard !s.isEmpty, s.count < 2048, !s.contains(" "), !s.contains("\n") else { return false }
        guard let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "ftp", "file"].contains(scheme),
              url.host != nil || scheme == "file"
        else { return false }
        return true
    }

    private static let hexRegex = try! NSRegularExpression(pattern: #"^#?[0-9a-fA-F]+$"#)
    private static let funcColorRegex = try! NSRegularExpression(
        pattern: #"^(rgba?|hsla?)\s*\([^\)]+\)$"#,
        options: [.caseInsensitive]
    )

    private static func isColor(_ s: String) -> Bool {
        let range = NSRange(s.startIndex..., in: s)
        if hexRegex.firstMatch(in: s, range: range) != nil {
            let clean = s.hasPrefix("#") ? String(s.dropFirst()) : s
            return [3, 4, 6, 8].contains(clean.count)
        }
        return funcColorRegex.firstMatch(in: s, range: range) != nil
    }

    private static let codeKeywords: [String] = [
        "function ", "def ", "class ", "import ", "const ", "let ", "var ",
        "if (", "for (", "while (", "return ", "public ", "private ", "static ",
        "struct ", "enum ", "@State", "#include", "#import", "println(", "console.log",
        "print(", "extension ", "protocol ", "=>", "->", "async ", "await ", "throws"
    ]

    private static func isCode(_ raw: String) -> Bool {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 || raw.count > 40 else { return false }

        var score = 0
        for k in codeKeywords where raw.contains(k) { score += 2 }

        let symbolChars: Set<Character> = ["{", "}", ";", "(", ")", "=", "<", ">"]
        let symbolCount = raw.reduce(0) { acc, c in symbolChars.contains(c) ? acc + 1 : acc }
        if raw.count > 0 {
            let density = Double(symbolCount) / Double(raw.count)
            if density > 0.06 { score += 2 }
        }

        let indented = lines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }.count
        if indented >= 2 { score += 1 }

        return score >= 3
    }
}
