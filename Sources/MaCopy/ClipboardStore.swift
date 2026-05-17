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

    private init() {
        startObserving()
    }

    func upsertCachedPreview(_ preview: LinkPreviewRecord) {
        previewsByHash[preview.urlHash] = preview
    }

    func removeCachedPreview(forHash hash: String) {
        previewsByHash.removeValue(forKey: hash)
    }

    private func startObserving() {
        let itemsObservation = ValueObservation.tracking { [recentLimit] db in
            try ClipboardItemRecord
                .order(ClipboardItemRecord.Columns.updatedAt.desc)
                .limit(recentLimit)
                .fetchAll(db)
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
