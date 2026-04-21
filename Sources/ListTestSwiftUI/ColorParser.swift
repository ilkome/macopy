import Foundation
import SwiftUI

struct ParsedColor {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var rgbString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        if alpha >= 0.999 {
            return "rgb(\(r), \(g), \(b))"
        }
        return String(format: "rgba(%d, %d, %d, %.2f)", r, g, b, alpha)
    }
}

enum ColorParser {
    static func parse(_ raw: String) -> ParsedColor? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hex = parseHex(trimmed) { return hex }
        if let fn = parseFunctional(trimmed) { return fn }
        return nil
    }

    static func isColor(_ raw: String) -> Bool {
        parse(raw) != nil
    }

    private static func parseHex(_ s: String) -> ParsedColor? {
        var str = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard !str.isEmpty, str.allSatisfy({ $0.isHexDigit }) else { return nil }
        switch str.count {
        case 3, 4:
            str = str.map { "\($0)\($0)" }.joined()
        case 6, 8:
            break
        default:
            return nil
        }
        guard let value = UInt64(str, radix: 16) else { return nil }
        if str.count == 6 {
            let r = Double((value >> 16) & 0xff) / 255
            let g = Double((value >> 8) & 0xff) / 255
            let b = Double(value & 0xff) / 255
            return ParsedColor(red: r, green: g, blue: b, alpha: 1)
        }
        let r = Double((value >> 24) & 0xff) / 255
        let g = Double((value >> 16) & 0xff) / 255
        let b = Double((value >> 8) & 0xff) / 255
        let a = Double(value & 0xff) / 255
        return ParsedColor(red: r, green: g, blue: b, alpha: a)
    }

    private static let functionalRegex = try! NSRegularExpression(
        pattern: #"^(rgba?|hsla?)\s*\(\s*([^)]+)\s*\)$"#,
        options: [.caseInsensitive]
    )

    private static func parseFunctional(_ s: String) -> ParsedColor? {
        let range = NSRange(s.startIndex..., in: s)
        guard let m = functionalRegex.firstMatch(in: s, range: range),
              let fnRange = Range(m.range(at: 1), in: s),
              let argsRange = Range(m.range(at: 2), in: s)
        else { return nil }
        let fn = s[fnRange].lowercased()
        let parts = s[argsRange]
            .split(whereSeparator: { $0 == "," || $0 == "/" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count == 3 || parts.count == 4 else { return nil }

        let alpha: Double = parts.count == 4 ? (component(parts[3]) ?? 1) : 1

        if fn.hasPrefix("rgb") {
            guard
                let r = component(parts[0]),
                let g = component(parts[1]),
                let b = component(parts[2])
            else { return nil }
            let divisor: Double = parts[0].hasSuffix("%") ? 1 : 255
            return ParsedColor(
                red: clamp(r / divisor),
                green: clamp(g / divisor),
                blue: clamp(b / divisor),
                alpha: clamp(alpha)
            )
        }

        if fn.hasPrefix("hsl") {
            let hRaw = parts[0].replacingOccurrences(of: "deg", with: "")
            guard
                let h = Double(hRaw),
                let s1 = component(parts[1]),
                let l1 = component(parts[2])
            else { return nil }
            let rgb = hslToRGB(h: h, s: clamp(s1), l: clamp(l1))
            return ParsedColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: clamp(alpha))
        }

        return nil
    }

    private static func component(_ s: String) -> Double? {
        if s.hasSuffix("%"), let v = Double(s.dropLast()) { return v / 100 }
        return Double(s)
    }

    private static func clamp(_ v: Double) -> Double {
        min(1, max(0, v))
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (r: Double, g: Double, b: Double) {
        let c = (1 - abs(2 * l - 1)) * s
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hh {
        case 0..<1: (r1, g1, b1) = (c, x, 0)
        case 1..<2: (r1, g1, b1) = (x, c, 0)
        case 2..<3: (r1, g1, b1) = (0, c, x)
        case 3..<4: (r1, g1, b1) = (0, x, c)
        case 4..<5: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        let m = l - c / 2
        return (r1 + m, g1 + m, b1 + m)
    }
}
