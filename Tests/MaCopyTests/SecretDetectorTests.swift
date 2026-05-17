import XCTest
@testable import MaCopy

final class SecretDetectorTests: XCTestCase {

    // MARK: - Positive cases (must be detected)

    func testDetectsJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        XCTAssertEqual(SecretDetector.detect(in: jwt), .jwt)
    }

    func testDetectsJWTInsideText() {
        let text = "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        XCTAssertEqual(SecretDetector.detect(in: text), .jwt)
    }

    func testDetectsAWSAccessKey() {
        XCTAssertEqual(SecretDetector.detect(in: "AKIAIOSFODNN7EXAMPLE"), .aws)
        XCTAssertEqual(SecretDetector.detect(in: "ASIAQ4F5BBBBBBBBBBBB"), .aws)
    }

    func testDetectsGitHubClassicPAT() {
        let token = "ghp_" + String(repeating: "a", count: 36)
        XCTAssertEqual(SecretDetector.detect(in: token), .githubClassic)
    }

    func testDetectsGitHubFineGrainedPAT() {
        let body = String(repeating: "A", count: 82)
        let token = "github_pat_" + body
        XCTAssertEqual(SecretDetector.detect(in: token), .githubFineGrained)
    }

    func testDetectsStripeKey() {
        let body = String(repeating: "x", count: 24)
        XCTAssertEqual(SecretDetector.detect(in: "sk_test_" + body), .stripe)
        XCTAssertEqual(SecretDetector.detect(in: "rk_live_" + body), .stripe)
        XCTAssertEqual(SecretDetector.detect(in: "pk_live_" + body), .stripe)
    }

    func testDetectsOpenAIKey() {
        let prefix = String(repeating: "a", count: 74)
        let suffix = String(repeating: "b", count: 74)
        XCTAssertEqual(SecretDetector.detect(in: "sk-proj-\(prefix)T3BlbkFJ\(suffix)"), .openai)
    }

    func testDetectsAnthropicKey() {
        let body = String(repeating: "A", count: 93)
        let token = "sk-ant-api03-\(body)AA"
        XCTAssertEqual(SecretDetector.detect(in: token), .anthropic)
    }

    func testDetectsGoogleAPIKey() {
        let body = String(repeating: "A", count: 35)
        XCTAssertEqual(SecretDetector.detect(in: "AIza" + body), .google)
    }

    func testDetectsHighEntropyToken() {
        // 64-char mixed charset random-looking string
        let token = "aB3xZ9-_kL4mN7pQ2rS5tU8vW1yA6bC0dE3fG_hI-jK4lM7nO9pQ2rS5tU8vWzZyXq"
        XCTAssertEqual(SecretDetector.detect(in: token), .highEntropy)
    }

    // MARK: - Negative cases (must NOT be detected)

    func testIgnoresPlainURL() {
        let url = "https://example.com/very/long/path/here?token=foo&utm_source=newsletter&utm_medium=email"
        XCTAssertNil(SecretDetector.detect(in: url))
    }

    func testIgnoresDataURI() {
        let dataURI = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        XCTAssertNil(SecretDetector.detect(in: dataURI))
    }

    func testIgnoresSHA256Hex() {
        let sha = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        XCTAssertNil(SecretDetector.detect(in: sha))
    }

    func testIgnoresSHA1Hex() {
        let sha = "da39a3ee5e6b4b0d3255bfef95601890afd80709"
        XCTAssertNil(SecretDetector.detect(in: sha))
    }

    func testIgnoresUUID() {
        XCTAssertNil(SecretDetector.detect(in: "550e8400-e29b-41d4-a716-446655440000"))
    }

    func testIgnoresPlainText() {
        XCTAssertNil(SecretDetector.detect(in: "Meeting notes from yesterday at 3pm. Discussed roadmap."))
    }

    func testIgnoresLowercaseOnlyToken() {
        // 32 chars, only lowercase: <3 charset classes
        XCTAssertNil(SecretDetector.detect(in: "abcdefghijklmnopqrstuvwxyzabcdef"))
    }

    func testIgnoresShortToken() {
        // <32 chars
        XCTAssertNil(SecretDetector.detect(in: "aB3xZ9-_kL4mN7"))
    }

    func testIgnoresCyrillicPath() {
        let path = "/Users/ilkome/Documents/works/brain/healh/Голодание/Варианты питаний"
        XCTAssertNil(SecretDetector.detect(in: path))
    }

    func testIgnoresAbsolutePath() {
        let path = "/Users/foo/Documents/projects/Whatever/very/deeply/nested/long/path"
        XCTAssertNil(SecretDetector.detect(in: path))
    }

    func testIgnoresTildePath() {
        let path = "~/Library/Application Support/MaCopy/very/long/deeply/nested/path"
        XCTAssertNil(SecretDetector.detect(in: path))
    }

    func testIgnoresLongCyrillicText() {
        let text = "Положи свой вариант рациона в /Users/ilkome/Documents/works/brain/healh/Голодание оформи как markdown"
        XCTAssertNil(SecretDetector.detect(in: text))
    }

    // MARK: - Entropy helper

    func testShannonEntropyOfRepeatedChar() {
        XCTAssertEqual(SecretDetector.shannonEntropy("aaaaaaaa"), 0.0, accuracy: 0.0001)
    }

    func testShannonEntropyOfTwoChars() {
        XCTAssertEqual(SecretDetector.shannonEntropy("ababab"), 1.0, accuracy: 0.0001)
    }

    // MARK: - Prefilter helper

    func testPrefilterRejectsShort() {
        XCTAssertFalse(SecretDetector.passesEntropyPrefilters("abc"))
    }

    func testPrefilterRejectsURL() {
        XCTAssertFalse(SecretDetector.passesEntropyPrefilters("https://example.com/foo/bar/baz/qux/very/long"))
    }

    func testPrefilterRejectsHexHash() {
        XCTAssertFalse(SecretDetector.passesEntropyPrefilters("e3b0c44298fc1c149afbf4c8996fb924"))
    }

    func testPrefilterAcceptsMixedCharsetToken() {
        XCTAssertTrue(SecretDetector.passesEntropyPrefilters("aB3xZ9-_kL4mN7pQ2rS5tU8vW1yA6bC0"))
    }
}
