import XCTest
@testable import MaCopy

@MainActor
final class PasterUsageTests: XCTestCase {
    private enum TestError: Error {
        case persistence
    }

    private final class Recorder: @unchecked Sendable {
        var copied: UUID?
        var pasted: UUID?
        var count = 0
    }

    private func item() -> ClipboardItemRecord {
        ClipboardItemRecord(contentHash: UUID().uuidString, kind: .text, text: "x", preview: "x")
    }

    private func dependencies(
        prepared: Bool = true,
        trusted: Bool = true,
        dispatched: Bool = true,
        copyRecorded: @escaping @MainActor @Sendable (UUID) throws -> Void = { _ in },
        pasteRecorded: @escaping @MainActor @Sendable (UUID) throws -> Void = { _ in }
    ) -> Paster.Dependencies {
        var dependencies = Paster.Dependencies()
        dependencies.preparePasteboard = { _ in prepared }
        dependencies.isTrusted = { trusted }
        dependencies.showAccessibilityAlert = {}
        dependencies.hidePanel = {}
        dependencies.dispatchPaste = { dispatched }
        dependencies.recordCopy = copyRecorded
        dependencies.recordPaste = pasteRecorded
        return dependencies
    }

    func testSuccessfulCopyOnlyRecordsCopy() {
        let item = item()
        let recorder = Recorder()
        let paster = Paster(dependencies: dependencies(
            copyRecorded: { recorder.copied = $0 },
            pasteRecorded: { recorder.pasted = $0 }
        ))

        XCTAssertTrue(paster.copyOnly(item))
        XCTAssertEqual(recorder.copied, item.id)
        XCTAssertNil(recorder.pasted)
    }

    func testFailedPreparationRecordsNothing() {
        let recorder = Recorder()
        let paster = Paster(dependencies: dependencies(
            prepared: false,
            copyRecorded: { _ in recorder.count += 1 },
            pasteRecorded: { _ in recorder.count += 1 }
        ))

        XCTAssertFalse(paster.copyOnly(item()))
        XCTAssertFalse(paster.paste(item()))
        XCTAssertEqual(recorder.count, 0)
    }

    func testSuccessfulImmediatePasteRecordsPasteOnly() {
        let item = item()
        let recorder = Recorder()
        let paster = Paster(dependencies: dependencies(
            copyRecorded: { _ in recorder.count += 1 },
            pasteRecorded: { recorder.pasted = $0 }
        ))

        XCTAssertTrue(paster.paste(item))
        XCTAssertEqual(recorder.pasted, item.id)
        XCTAssertEqual(recorder.count, 0)
    }

    func testMissingAccessibilityOrDispatchFailureDoesNotRecordPaste() {
        let recorder = Recorder()
        let untrusted = Paster(dependencies: dependencies(
            trusted: false,
            pasteRecorded: { _ in recorder.count += 1 }
        ))
        let failedDispatch = Paster(dependencies: dependencies(
            dispatched: false,
            pasteRecorded: { _ in recorder.count += 1 }
        ))

        XCTAssertTrue(untrusted.paste(item()))
        XCTAssertTrue(failedDispatch.paste(item()))
        XCTAssertEqual(recorder.count, 0)
    }

    func testCounterPersistenceDoesNotChangeSuccessfulActionResult() {
        let paster = Paster(dependencies: dependencies(
            copyRecorded: { _ in throw TestError.persistence },
            pasteRecorded: { _ in throw TestError.persistence }
        ))

        XCTAssertTrue(paster.copyOnly(item()))
        XCTAssertTrue(paster.paste(item()))
    }
}
