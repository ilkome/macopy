import Foundation

/// Bounds unbounded growth of the database and the encrypted image directory. Without this,
/// `clipboard_items` and `link_previews` accumulate forever even though only the newest 2000
/// items are ever shown, slowing the startup backfill scan, migrations and disk usage.
///
/// Runs off the main thread (DatabasePool is thread-safe); call from a detached task.
enum RetentionService {
    static let itemLimit = 2000
    /// Link previews are cheap to refetch on demand, so we drop stale ones by age.
    static let previewMaxAge: TimeInterval = 60 * 60 * 24 * 30  // 30 days

    static func prune() {
        let removedImagePaths = (try? ClipboardItemRepository.pruneToLimit(keep: itemLimit)) ?? []
        for path in removedImagePaths {
            ImageStore.delete(filename: path)
            ImageStore.delete(filename: ImageCache.thumbFilename(for: path))
        }
        try? LinkPreviewRepository.pruneOlderThan(previewMaxAge)
        sweepOrphanImages()
    }

    /// Deletes encrypted image files (and their `.thumb` companions) that no row references -
    /// e.g. a write that succeeded before its row insert failed, or leftovers from older builds.
    /// Bails on a query error rather than risk wiping live files.
    private static func sweepOrphanImages() {
        guard let valid = try? ClipboardItemRepository.allImagePaths() else { return }
        let dir = Storage.appSupportURL.appendingPathComponent("images")
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for file in files {
            guard file.hasSuffix(ImageStore.encryptedSuffix) else { continue }
            var base = String(file.dropLast(ImageStore.encryptedSuffix.count))
            if base.hasSuffix(".thumb") { base = String(base.dropLast(".thumb".count)) }
            if !valid.contains(base) {
                try? fm.removeItem(at: dir.appendingPathComponent(file))
            }
        }
    }
}
