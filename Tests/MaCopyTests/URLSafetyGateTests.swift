import XCTest
@testable import MaCopy

final class URLSafetyGateTests: XCTestCase {

    // MARK: - IPv4 parsing and CIDR

    func testParsesIPv4Literal() {
        guard case .v4(let v)? = URLSafetyGate.parseIPLiteral("127.0.0.1") else {
            return XCTFail("expected v4")
        }
        XCTAssertEqual(v, 0x7F000001)
    }

    func testBlocksIPv4PrivateRanges() {
        let blocked = [
            "0.0.0.0", "0.255.255.255",
            "10.0.0.1", "10.255.255.255",
            "100.64.0.1", "100.127.255.254",
            "127.0.0.1", "127.255.255.255",
            "169.254.0.1", "169.254.255.255",
            "172.16.0.1", "172.31.255.255",
            "192.0.0.1", "192.0.2.1",
            "192.168.0.1", "192.168.255.255",
            "198.18.0.1", "198.19.255.255",
            "198.51.100.1",
            "203.0.113.1",
            "224.0.0.1", "239.255.255.255",
            "240.0.0.1", "255.255.255.255"
        ]
        for ip in blocked {
            guard case .v4(let v)? = URLSafetyGate.parseIPLiteral(ip) else {
                XCTFail("could not parse \(ip)")
                continue
            }
            XCTAssertTrue(URLSafetyGate.isBlockedIPv4(v), "expected blocked: \(ip)")
        }
    }

    func testAllowsIPv4PublicRanges() {
        let allowed = [
            "1.1.1.1",
            "8.8.8.8",
            "100.63.255.255",
            "100.128.0.0",
            "172.15.255.255",
            "172.32.0.0",
            "198.17.255.255",
            "198.20.0.0",
            "198.51.99.255",
            "198.51.101.0",
            "203.0.112.255",
            "203.0.114.0",
            "223.255.255.255"
        ]
        for ip in allowed {
            guard case .v4(let v)? = URLSafetyGate.parseIPLiteral(ip) else {
                XCTFail("could not parse \(ip)")
                continue
            }
            XCTAssertFalse(URLSafetyGate.isBlockedIPv4(v), "expected allowed: \(ip)")
        }
    }

    // MARK: - IPv6 parsing and CIDR

    func testParsesIPv6Literal() {
        guard case .v6(let bytes)? = URLSafetyGate.parseIPLiteral("fe80::1") else {
            return XCTFail("expected v6")
        }
        XCTAssertEqual(bytes.count, 16)
        XCTAssertEqual(bytes[0], 0xFE)
        XCTAssertEqual(bytes[1], 0x80)
        XCTAssertEqual(bytes[15], 0x01)
    }

    func testParsesIPv6WithBrackets() {
        XCTAssertNotNil(URLSafetyGate.parseIPLiteral("[fe80::1]"))
        XCTAssertNotNil(URLSafetyGate.parseIPLiteral("[::1]"))
    }

    func testParsesIPv6WithZoneId() {
        XCTAssertNotNil(URLSafetyGate.parseIPLiteral("fe80::1%en0"))
    }

    func testBlocksIPv6Ranges() {
        let blocked = [
            "::",
            "::1",
            "fe80::1",
            "fe80::dead:beef",
            "febf:ffff::1",
            "fc00::1",
            "fd00::1",
            "fdff:ffff::1",
            "ff02::1",
            "ff00::1",
            "64:ff9b::1.2.3.4",
            "100::1",
            "2001::1",
            "2001:db8::1"
        ]
        for ip in blocked {
            guard case .v6(let bytes)? = URLSafetyGate.parseIPLiteral(ip) else {
                XCTFail("could not parse \(ip)")
                continue
            }
            XCTAssertTrue(URLSafetyGate.isBlockedIPv6(bytes), "expected blocked: \(ip)")
        }
    }

    func testAllowsIPv6PublicRanges() {
        let allowed = [
            "2606:4700:4700::1111",
            "2001:4860:4860::8888"
        ]
        for ip in allowed {
            guard case .v6(let bytes)? = URLSafetyGate.parseIPLiteral(ip) else {
                XCTFail("could not parse \(ip)")
                continue
            }
            XCTAssertFalse(URLSafetyGate.isBlockedIPv6(bytes), "expected allowed: \(ip)")
        }
    }

    // MARK: - IPv4-mapped IPv6 (critical bypass)

    func testIPv4MappedLoopbackIsBlocked() {
        guard case .v6(let bytes)? = URLSafetyGate.parseIPLiteral("::ffff:127.0.0.1") else {
            return XCTFail("could not parse mapped loopback")
        }
        XCTAssertTrue(URLSafetyGate.isBlockedIPv6(bytes))
    }

    func testIPv4MappedHexLoopbackIsBlocked() {
        guard case .v6(let bytes)? = URLSafetyGate.parseIPLiteral("::ffff:7f00:1") else {
            return XCTFail("could not parse mapped loopback in hex form")
        }
        XCTAssertTrue(URLSafetyGate.isBlockedIPv6(bytes))
    }

    func testIPv4MappedPrivateIsBlocked() {
        guard case .v6(let bytes)? = URLSafetyGate.parseIPLiteral("::ffff:10.0.0.1") else {
            return XCTFail("could not parse mapped private")
        }
        XCTAssertTrue(URLSafetyGate.isBlockedIPv6(bytes))
    }

    func testIPv4MappedCGNATIsBlocked() {
        guard case .v6(let bytes)? = URLSafetyGate.parseIPLiteral("::ffff:100.64.0.1") else {
            return XCTFail("could not parse mapped CGNAT")
        }
        XCTAssertTrue(URLSafetyGate.isBlockedIPv6(bytes))
    }

    func testIPv4MappedPublicIsAllowed() {
        guard case .v6(let bytes)? = URLSafetyGate.parseIPLiteral("::ffff:8.8.8.8") else {
            return XCTFail("could not parse mapped public")
        }
        XCTAssertFalse(URLSafetyGate.isBlockedIPv6(bytes))
    }

    // MARK: - Non-IP host

    func testNonIPHostReturnsNil() {
        XCTAssertNil(URLSafetyGate.parseIPLiteral("github.com"))
        XCTAssertNil(URLSafetyGate.parseIPLiteral(""))
        XCTAssertNil(URLSafetyGate.parseIPLiteral("not.an.ip.address"))
    }

    // MARK: - validateResolved with literals (no DNS)

    func testValidateResolvedBlocksLiteralLoopback() async {
        let decision = await URLSafetyGate.validateResolved(host: "127.0.0.1")
        XCTAssertEqual(decision, .blockPrivateIP)
    }

    func testValidateResolvedBlocksLiteralIPv6Loopback() async {
        let decision = await URLSafetyGate.validateResolved(host: "::1")
        XCTAssertEqual(decision, .blockPrivateIP)
    }

    func testValidateResolvedBlocksIPv4MappedLoopback() async {
        let decision = await URLSafetyGate.validateResolved(host: "::ffff:7f00:1")
        XCTAssertEqual(decision, .blockPrivateIP)
    }

    func testValidateResolvedBlocksCGNAT() async {
        let decision = await URLSafetyGate.validateResolved(host: "100.64.0.1")
        XCTAssertEqual(decision, .blockPrivateIP)
    }

    func testValidateResolvedBlocksBenchmark() async {
        let decision = await URLSafetyGate.validateResolved(host: "198.18.0.1")
        XCTAssertEqual(decision, .blockPrivateIP)
    }

    func testValidateResolvedBlocksLinkLocalIPv6() async {
        let decision = await URLSafetyGate.validateResolved(host: "fe80::1")
        XCTAssertEqual(decision, .blockPrivateIP)
    }

    func testValidateResolvedBlocksULA() async {
        let decision = await URLSafetyGate.validateResolved(host: "fc00::1")
        XCTAssertEqual(decision, .blockPrivateIP)
    }

    func testValidateResolvedBlocksEmptyHost() async {
        let decision = await URLSafetyGate.validateResolved(host: nil)
        XCTAssertEqual(decision, .blockNoHost)
    }

    // MARK: - URLNormalizer regression after refactor

    func testNormalizerStillBlocksIPv4Literals() {
        XCTAssertFalse(URLNormalizer.shouldFetchPreview("http://10.0.0.1"))
        XCTAssertFalse(URLNormalizer.shouldFetchPreview("http://127.0.0.1"))
        XCTAssertFalse(URLNormalizer.shouldFetchPreview("http://172.16.0.1"))
        XCTAssertFalse(URLNormalizer.shouldFetchPreview("http://192.168.1.1"))
        XCTAssertFalse(URLNormalizer.shouldFetchPreview("http://169.254.169.254"))
        XCTAssertFalse(URLNormalizer.shouldFetchPreview("http://0.0.0.0"))
    }

    func testNormalizerBlocksNewlyAddedIPv4Ranges() {
        XCTAssertFalse(URLNormalizer.shouldFetchPreview("http://100.64.0.1"))
        XCTAssertFalse(URLNormalizer.shouldFetchPreview("http://198.18.0.1"))
        XCTAssertFalse(URLNormalizer.shouldFetchPreview("http://224.0.0.1"))
        XCTAssertFalse(URLNormalizer.shouldFetchPreview("http://255.255.255.255"))
    }

    func testNormalizerAllowsPublicHost() {
        XCTAssertTrue(URLNormalizer.shouldFetchPreview("https://github.com"))
        XCTAssertTrue(URLNormalizer.shouldFetchPreview("https://www.apple.com/swift"))
    }
}
