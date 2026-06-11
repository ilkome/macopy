import Foundation
import GRDB
import Combine
import os

@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    nonisolated private static let logger = Logger(subsystem: "dev.ilkome.MaCopy", category: "storage")

    @Published private(set) var items: [ClipboardItemRecord] = []
    @Published private(set) var previewsByHash: [String: LinkPreviewRecord] = [:]
    @Published private(set) var dataVersion: Int = 0

    private var itemsCancellable: AnyDatabaseCancellable?
    private let recentLimit = 2000

    // List rows only need preview-length data for rendering, sectioning and fuzzy
    // search; the cap keeps a single multi-MB clip from bloating the published array
    // and being re-decoded/compared on every write. Full text is loaded by id at
    // paste time and in the preview pane. The OCR cap matches SearchEngine.makeInputs.
    nonisolated static let listTextCap = 4096
    nonisolated static let listOCRCap = 500

    private init() {
        startObserving()
    }

    func upsertCachedPreview(_ preview: LinkPreviewRecord) {
        // No dataVersion bump: cards and DomainRow observe previewsByHash directly, so a
        // preview arriving must not trigger a full O(n) list recompute (each URL fetch
        // would otherwise cost two passes - pending + finalize).
        previewsByHash[preview.urlHash] = preview
    }

    func removeCachedPreview(forHash hash: String) {
        previewsByHash.removeValue(forKey: hash)
    }

    private func startObserving() {
        // WARNING: these records carry a capped text/ocrText excerpt - never persist
        // them back. All writes go through ClipboardItemRepository by id + column.
        let itemsObservation = ValueObservation.tracking { [recentLimit] db in
            try SQLRequest<ClipboardItemRecord>(literal: """
                SELECT id, createdAt, updatedAt, contentHash, kindRaw,
                       substr(text, 1, \(ClipboardStore.listTextCap)) AS text,
                       preview, imagePath, imageWidth, imageHeight,
                       substr(ocrText, 1, \(ClipboardStore.listOCRCap)) AS ocrText,
                       sourceAppBundleId, sourceAppName, sourceAppIconPath,
                       sourceFilePath, byteSize, isFavorite, comment
                FROM clipboard_items
                ORDER BY updatedAt DESC
                LIMIT \(recentLimit)
                """).fetchAll(db)
        }
        itemsCancellable = itemsObservation.start(
            in: AppDatabase.shared,
            scheduling: .async(onQueue: DispatchQueue.main),
            onError: { error in
                Self.logger.error("items observation failed: \(error, privacy: .private)")
            },
            onChange: { [weak self] items in
                MainActor.assumeIsolated {
                    self?.items = items
                    self?.dataVersion &+= 1
                }
            }
        )
    }
}
