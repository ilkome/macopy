import XCTest
@testable import MaCopy

@MainActor
final class IconCacheTests: XCTestCase {

    func testSanitizeKeepsValidBundleId() {
        XCTAssertEqual(IconCache.sanitize("com.apple.Safari"), "com.apple.Safari")
        XCTAssertEqual(IconCache.sanitize("dev.ilkome.MaCopy"), "dev.ilkome.MaCopy")
        XCTAssertEqual(IconCache.sanitize("foo-bar.baz-qux"), "foo-bar.baz-qux")
    }

    func testSanitizeReplacesPathSeparators() {
        XCTAssertEqual(IconCache.sanitize("a/b/c"), "a_b_c")
        XCTAssertEqual(IconCache.sanitize("a\\b\\c"), "a_b_c")
    }

    func testSanitizeReplacesParentTraversal() {
        XCTAssertEqual(IconCache.sanitize("../../etc/passwd"), ".._.._etc_passwd")
        XCTAssertEqual(IconCache.sanitize("..\\..\\windows"), ".._.._windows")
    }

    func testSanitizeReplacesNullsAndControls() {
        XCTAssertEqual(IconCache.sanitize("foo\u{0000}bar"), "foo_bar")
        XCTAssertEqual(IconCache.sanitize("foo\nbar\tbaz"), "foo_bar_baz")
    }

    func testSanitizeReplacesNonAsciiAndWhitespace() {
        XCTAssertEqual(IconCache.sanitize("com.app пример"), "com.app_______")
        XCTAssertEqual(IconCache.sanitize("foo bar"), "foo_bar")
    }

    func testSanitizeLimitsLength() {
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(IconCache.sanitize(long).count, 200)
    }

    func testSanitizeEmpty() {
        XCTAssertEqual(IconCache.sanitize(""), "")
    }
}
