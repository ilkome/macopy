import XCTest
@testable import MaCopy

@MainActor
final class ClipboardMonitorTests: XCTestCase {

    private struct Fixture {
        let root: URL
        let allowed: URL
    }

    private func makeFixture() throws -> Fixture {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("MaCopyTests-\(UUID().uuidString)", isDirectory: true)
        let allowed = root.appendingPathComponent("Pictures", isDirectory: true)
        try fm.createDirectory(at: allowed, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Fixture(root: root, allowed: allowed)
    }

    private func roots(_ f: Fixture) -> [String] {
        [f.allowed.resolvingSymlinksInPath().standardizedFileURL.path]
    }

    func testAllowsFileInsideAllowedRoot() throws {
        let f = try makeFixture()
        let url = f.allowed.appendingPathComponent("photo.png")
        XCTAssertTrue(ClipboardMonitor.isAllowedImageFileURL(url, allowedRoots: roots(f)))
    }

    func testAllowsNestedFileInsideAllowedRoot() throws {
        let f = try makeFixture()
        let url = f.allowed.appendingPathComponent("sub/dir/photo.png")
        XCTAssertTrue(ClipboardMonitor.isAllowedImageFileURL(url, allowedRoots: roots(f)))
    }

    func testRejectsFileOutsideAllowedRoot() throws {
        let f = try makeFixture()
        let outside = f.root.appendingPathComponent("Library/Keychains/login.keychain-db.png")
        XCTAssertFalse(ClipboardMonitor.isAllowedImageFileURL(outside, allowedRoots: roots(f)))
    }

    func testRejectsParentTraversal() throws {
        let f = try makeFixture()
        let traversal = f.allowed.appendingPathComponent("../Library/Keychains/login.keychain-db.png")
        XCTAssertFalse(ClipboardMonitor.isAllowedImageFileURL(traversal, allowedRoots: roots(f)))
    }

    func testRejectsSymlinkOutsideAllowedRoot() throws {
        let f = try makeFixture()
        let secretDir = f.root.appendingPathComponent("Library/Keychains", isDirectory: true)
        try FileManager.default.createDirectory(at: secretDir, withIntermediateDirectories: true)
        let secret = secretDir.appendingPathComponent("login.keychain-db")
        try Data("supersecret".utf8).write(to: secret)

        let symlink = f.allowed.appendingPathComponent("evil.png")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: secret)

        XCTAssertFalse(ClipboardMonitor.isAllowedImageFileURL(symlink, allowedRoots: roots(f)))
    }

    func testRejectsNonFileURL() throws {
        let f = try makeFixture()
        let httpURL = URL(string: "https://evil.example/img.png")!
        XCTAssertFalse(ClipboardMonitor.isAllowedImageFileURL(httpURL, allowedRoots: roots(f)))
    }

    func testRejectsSiblingDirectoryWithPrefixMatch() throws {
        let f = try makeFixture()
        let sibling = f.root.appendingPathComponent("PicturesEvil/photo.png")
        XCTAssertFalse(ClipboardMonitor.isAllowedImageFileURL(sibling, allowedRoots: roots(f)))
    }
}
