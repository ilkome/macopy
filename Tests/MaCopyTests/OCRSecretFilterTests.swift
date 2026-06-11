import XCTest
@testable import MaCopy

final class OCRSecretFilterTests: XCTestCase {

    func testRedactedSentinelFormat() {
        for kind in SecretKind.allCases {
            let sentinel = SecretDetector.redactedSentinel(for: kind)
            XCTAssertEqual(sentinel, "[Hidden: \(kind.rawValue)]")
            XCTAssertNil(
                SecretDetector.detect(in: sentinel),
                "Sentinel must not itself be classified as a secret (\(kind.rawValue))"
            )
        }
    }

    func testSanitizesJWTInMultilineOCROutput() {
        let recognized = """
        Authorization header captured below.
        Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
        Issued by: identity.example.com
        """
        let result = OCRService.sanitizedOCRText(recognized, filterSecrets: true)
        XCTAssertEqual(result.redactedKind, .jwt)
        XCTAssertEqual(result.text, "[Hidden: jwt]")
    }

    func testSanitizesAWSAccessKeyInOCROutput() {
        let recognized = "Console screenshot — AKIAIOSFODNN7EXAMPLE — region us-east-1"
        let result = OCRService.sanitizedOCRText(recognized, filterSecrets: true)
        XCTAssertEqual(result.redactedKind, .aws)
        XCTAssertEqual(result.text, "[Hidden: aws]")
    }

    func testSanitizesHighEntropyToken() {
        let recognized = "API key shown in screenshot:\naB3xZ9-_kL4mN7pQ2rS5tU8vW1yA6bC0dE3fG_hI-jK4lM7nO9pQ2rS5tU8vWzZyXq"
        let result = OCRService.sanitizedOCRText(recognized, filterSecrets: true)
        XCTAssertEqual(result.redactedKind, .highEntropy)
        XCTAssertEqual(result.text, "[Hidden: high_entropy]")
    }

    func testPassesBenignTextThrough() {
        let recognized = """
        Meeting notes from yesterday at 3pm.
        Discussed roadmap, milestones for Q3, and onboarding plan.
        """
        let result = OCRService.sanitizedOCRText(recognized, filterSecrets: true)
        XCTAssertNil(result.redactedKind)
        XCTAssertEqual(result.text, recognized)
    }

    func testRespectsFilterDisabledFlag() {
        let recognized = "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let result = OCRService.sanitizedOCRText(recognized, filterSecrets: false)
        XCTAssertNil(result.redactedKind)
        XCTAssertEqual(result.text, recognized)
    }

    func testEmptyOCRTextIsUnchanged() {
        let result = OCRService.sanitizedOCRText("", filterSecrets: true)
        XCTAssertNil(result.redactedKind)
        XCTAssertEqual(result.text, "")
    }
}
