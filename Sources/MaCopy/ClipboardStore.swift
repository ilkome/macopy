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

    // Folder list + membership maps, observed off the folders/folder_items tables.
    @Published private(set) var folders: [FolderRecord] = []
    @Published private(set) var folderMembership: [UUID: Set<UUID>] = [:]      // folderID -> itemIDs
    @Published private(set) var itemFolderMembership: [UUID: Set<UUID>] = [:]  // itemID -> folderIDs
    // Separate signal: membership changes must NOT bump dataVersion (which drives the full
    // O(n) item-list recompute), exactly like previewsByHash. The folder panes react to this.
    @Published private(set) var folderVersion: Int = 0

    private var itemsCancellable: AnyDatabaseCancellable?
    private var foldersCancellable: AnyDatabaseCancellable?
    private let recentLimit = 2000

    // List rows only need preview-length data for rendering, sectioning and fuzzy
    // search; the cap keeps a single multi-MB clip from bloating the published array
    // and being re-decoded/compared on every write. Full text is loaded by id at
    // paste time and in the preview pane. The OCR cap matches SearchEngine.makeInputs.
    nonisolated static let listTextCap = 4096
    nonisolated static let listOCRCap = 500

    private init() {
        startObserving()
        startObservingFolders()
    }

    // MARK: - Folders

    func isMember(folderId: UUID, itemId: UUID) -> Bool {
        folderMembership[folderId]?.contains(itemId) ?? false
    }

    @discardableResult
    func createFolder(name: String) -> FolderRecord? {
        try? FolderRepository.createFolder(name: name)
    }

    func renameFolder(id: UUID, name: String) {
        try? FolderRepository.renameFolder(id: id, name: name)
    }

    func deleteFolder(id: UUID) {
        try? FolderRepository.deleteFolder(id: id)
    }

    func toggleMembership(folderId: UUID, itemId: UUID) {
        _ = try? FolderRepository.toggleMembership(folderId: folderId, itemId: itemId)
    }

    func addToFolder(folderId: UUID, itemId: UUID) {
        try? FolderRepository.addMembership(folderId: folderId, itemId: itemId)
    }

    private func startObservingFolders() {
        let observation = ValueObservation.tracking { db -> ([FolderRecord], [FolderItemRecord]) in
            let folders = try FolderRecord
                .order(FolderRecord.Columns.sortIndex)
                .fetchAll(db)
            let memberships = try FolderItemRecord.fetchAll(db)
            return (folders, memberships)
        }
        foldersCancellable = observation.start(
            in: AppDatabase.shared,
            scheduling: .async(onQueue: DispatchQueue.main),
            onError: { error in
                Self.logger.error("folders observation failed: \(error, privacy: .private)")
            },
            onChange: { [weak self] result in
                MainActor.assumeIsolated {
                    self?.applyFolderSnapshot(folders: result.0, memberships: result.1)
                }
            }
        )
    }

    private func applyFolderSnapshot(folders: [FolderRecord], memberships: [FolderItemRecord]) {
        self.folders = folders
        var byFolder: [UUID: Set<UUID>] = [:]
        var byItem: [UUID: Set<UUID>] = [:]
        for m in memberships {
            byFolder[m.folderId, default: []].insert(m.itemId)
            byItem[m.itemId, default: []].insert(m.folderId)
        }
        self.folderMembership = byFolder
        self.itemFolderMembership = byItem
        self.folderVersion &+= 1
    }

    func upsertCachedPreview(_ preview: LinkPreviewRecord) {
        // No dataVersion bump: cards and DomainRow observe previewsByHash directly, so a
        // preview arriving must not trigger a full O(n) list recompute (each URL fetch
        // would otherwise cost two passes - pending + finalize).
        //
        // Strip the image/icon blobs: a URL-heavy session would otherwise accumulate hundreds
        // of MB of PNGs here for its whole lifetime. Only metadata (title/site/summary/status)
        // stays in memory; the card loads its blob from the DB and DomainRow uses FaviconCache.
        var meta = preview
        meta.imageData = nil
        meta.iconData = nil
        previewsByHash[preview.urlHash] = meta
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
