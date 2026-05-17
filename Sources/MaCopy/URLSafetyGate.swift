import Foundation

enum URLSafetyGate {
    typealias IPAddress = IPClassifier.IPAddress

    enum Decision: Sendable, Equatable {
        case allow
        case blockNoHost
        case blockUnsupportedScheme
        case blockPrivateIP
        case blockResolveFailed
    }

    static func validateResolved(host: String?, timeout: TimeInterval = 3) async -> Decision {
        guard let host = host, !host.isEmpty else { return .blockNoHost }

        if let literal = IPClassifier.parseIPLiteral(host) {
            return IPClassifier.isBlockedAddress(literal) ? .blockPrivateIP : .allow
        }

        let addresses = await DNSResolver.resolveAll(host: host, timeout: timeout)
        if addresses.isEmpty { return .blockResolveFailed }

        for addr in addresses {
            if IPClassifier.isBlockedAddress(addr) { return .blockPrivateIP }
        }
        return .allow
    }

    static func parseIPLiteral(_ host: String) -> IPAddress? {
        IPClassifier.parseIPLiteral(host)
    }

    static func isBlockedAddress(_ addr: IPAddress) -> Bool {
        IPClassifier.isBlockedAddress(addr)
    }

    static func isBlockedIPv4(_ addr: UInt32) -> Bool {
        IPClassifier.isBlockedIPv4(addr)
    }

    static func isBlockedIPv6(_ bytes: [UInt8]) -> Bool {
        IPClassifier.isBlockedIPv6(bytes)
    }

    static func resolveAll(host: String, timeout: TimeInterval = 3) async -> [IPAddress] {
        await DNSResolver.resolveAll(host: host, timeout: timeout)
    }
}
