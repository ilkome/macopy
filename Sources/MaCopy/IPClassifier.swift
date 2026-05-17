import Darwin
import Foundation

enum IPClassifier {
    enum IPAddress: Sendable, Equatable {
        case v4(UInt32)
        case v6([UInt8])
    }

    static func parseIPLiteral(_ host: String) -> IPAddress? {
        var stripped = host
        if stripped.hasPrefix("[") && stripped.hasSuffix("]") {
            stripped = String(stripped.dropFirst().dropLast())
        }
        if let percent = stripped.firstIndex(of: "%") {
            stripped = String(stripped[..<percent])
        }

        var v4 = in_addr()
        if stripped.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 {
            return .v4(UInt32(bigEndian: v4.s_addr))
        }

        var v6 = in6_addr()
        if stripped.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 {
            var bytes = [UInt8](repeating: 0, count: 16)
            withUnsafePointer(to: &v6) { ptr in
                ptr.withMemoryRebound(to: UInt8.self, capacity: 16) { byte in
                    for i in 0..<16 { bytes[i] = byte[i] }
                }
            }
            return .v6(bytes)
        }
        return nil
    }

    static func isBlockedAddress(_ addr: IPAddress) -> Bool {
        switch addr {
        case .v4(let v): return isBlockedIPv4(v)
        case .v6(let v): return isBlockedIPv6(v)
        }
    }

    static func isBlockedIPv4(_ addr: UInt32) -> Bool {
        let top = UInt8((addr >> 24) & 0xFF)
        let second = UInt8((addr >> 16) & 0xFF)
        let third = UInt8((addr >> 8) & 0xFF)

        if top == 0 { return true }
        if top == 10 { return true }
        if top == 100 && (64...127).contains(second) { return true }
        if top == 127 { return true }
        if top == 169 && second == 254 { return true }
        if top == 172 && (16...31).contains(second) { return true }
        if top == 192 && second == 0 && (third == 0 || third == 2) { return true }
        if top == 192 && second == 168 { return true }
        if top == 198 && (second == 18 || second == 19) { return true }
        if top == 198 && second == 51 && third == 100 { return true }
        if top == 203 && second == 0 && third == 113 { return true }
        if top >= 224 { return true }
        return false
    }

    static func isBlockedIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }

        if bytes.allSatisfy({ $0 == 0 }) { return true }

        if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true }

        if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
            let v4 = (UInt32(bytes[12]) << 24)
                | (UInt32(bytes[13]) << 16)
                | (UInt32(bytes[14]) << 8)
                | UInt32(bytes[15])
            return isBlockedIPv4(v4)
        }

        if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true }
        if (bytes[0] & 0xFE) == 0xFC { return true }
        if bytes[0] == 0xFF { return true }

        if bytes[0] == 0x00 && bytes[1] == 0x64 && bytes[2] == 0xFF && bytes[3] == 0x9B
            && bytes[4..<12].allSatisfy({ $0 == 0 }) {
            return true
        }

        if bytes[0] == 0x01 && bytes[1] == 0x00 && bytes[2..<8].allSatisfy({ $0 == 0 }) {
            return true
        }

        if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0D && bytes[3] == 0xB8 {
            return true
        }

        if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x00 && bytes[3] == 0x00 {
            return true
        }

        return false
    }
}
