import AppKit
@preconcurrency import LinkPresentation

@MainActor
final class LinkPreviewService {
    static let shared = LinkPreviewService()

    private var inFlight: [String: Task<Void, Never>] = [:]

    private init() {}

    func fetchIfNeeded(for rawURL: String, force: Bool = false) {
        guard AppSettings.shared.linkPreviewsEnabled else { return }
        guard URLNormalizer.shouldFetchPreview(rawURL) else {
            markSkipped(rawURL)
            return
        }
        let hash = URLNormalizer.hash(rawURL)
        if let existing = inFlight[hash] {
            if !force { return }
            existing.cancel()
        }

        if let existing = try? LinkPreviewRepository.findPreview(byHash: hash) {
            if !force && existing.status == .ok { return }
            if !force,
               existing.status == .failed,
               Date().timeIntervalSince(existing.fetchedAt) < 30 {
                return
            }
            var updated = existing
            updated.status = .pending
            persist(updated)
        } else {
            persist(LinkPreviewRecord(
                urlHash: hash,
                url: URLNormalizer.normalize(rawURL),
                hostname: URLNormalizer.normalizedHost(rawURL),
                status: .pending
            ))
        }

        inFlight[hash] = Task { await self.fetch(rawURL: rawURL, hash: hash) }
    }

    func cancel(rawURL: String) {
        let hash = URLNormalizer.hash(rawURL)
        inFlight[hash]?.cancel()
    }

    /// Fetches previews for recent URLs that don't have one yet. Runs detached after a short
    /// delay so it never blocks app launch; the DB diff is done off-main with two narrow queries
    /// (existing hashes + newest URL strings) instead of a full url-row fetch plus an N+1 of
    /// point reads; concurrency is bounded so first-enable doesn't storm LPMetadataProvider.
    nonisolated private static let backfillWindow = 200
    nonisolated private static let backfillConcurrency = 3

    func backfillPending() {
        guard AppSettings.shared.linkPreviewsEnabled else { return }
        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let existing = try? LinkPreviewRepository.existingHashes(),
                  let urls = try? ClipboardItemRepository.recentURLStrings(limit: Self.backfillWindow)
            else { return }
            let toFetch = urls.filter { !$0.isEmpty && !existing.contains(URLNormalizer.hash($0)) }
            guard !toFetch.isEmpty else { return }
            await self?.runBackfill(urls: toFetch)
        }
    }

    /// Processes the URLs in chunks: kick off a chunk through the normal fetch path, then await
    /// all of its in-flight tasks before starting the next - so at most `backfillConcurrency`
    /// network fetches run at once. Stays on the main actor; the heavy work runs off-main inside
    /// each fetch task.
    private func runBackfill(urls: [String]) async {
        var index = 0
        while index < urls.count {
            let end = min(index + Self.backfillConcurrency, urls.count)
            var tasks: [Task<Void, Never>] = []
            for raw in urls[index..<end] {
                fetchIfNeeded(for: raw)
                if let task = inFlight[URLNormalizer.hash(raw)] { tasks.append(task) }
            }
            for task in tasks { await task.value }
            index = end
        }
    }

    private func fetch(rawURL: String, hash: String) async {
        defer { inFlight.removeValue(forKey: hash) }
        guard let url = URLNormalizer.parse(rawURL) else {
            finalize(hash: hash, result: .failure)
            return
        }
        if Task.isCancelled { return }

        guard await URLSafetyGate.validateResolved(host: url.host) == .allow else {
            finalize(hash: hash, result: .failure)
            return
        }
        if Task.isCancelled { return }

        async let ogTask = OpenGraphParser.fetch(url: url)
        async let lpTask = Self.fetchLPMetadata(for: url)
        let og = await ogTask
        let lp = await lpTask
        if Task.isCancelled { return }

        let title = og?.title ?? lp?.title
        let summary = og?.description
        let siteName = og?.siteName ?? lp?.url?.host ?? lp?.originalURL?.host ?? url.host

        var imageData: Data?
        if let ogImage = og?.imageURL {
            imageData = await Self.downloadImage(from: ogImage)
        }
        if imageData == nil, let provider = lp?.imageProvider {
            imageData = await LinkPreviewImageLoader.load(from: provider)
        }
        let iconData = await LinkPreviewImageLoader.load(from: lp?.iconProvider)
        if Task.isCancelled { return }

        let hasAny = title != nil || summary != nil || imageData != nil || iconData != nil
        finalize(
            hash: hash,
            result: hasAny
                ? .success(title: title, siteName: siteName, summary: summary, imageData: imageData, iconData: iconData)
                : .failure
        )
    }

    private nonisolated static func fetchLPMetadata(for url: URL) async -> LPLinkMetadata? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        return try? await provider.startFetchingMetadata(for: url)
    }

    private nonisolated static func downloadImage(from url: URL) async -> Data? {
        guard let (data, _) = await SafeFetcher.fetch(url: url, maxBytes: 2 * 1024 * 1024) else {
            return nil
        }
        return LinkPreviewImageLoader.encodePNG(data: data)
    }

    private enum FetchResult {
        case success(title: String?, siteName: String?, summary: String?, imageData: Data?, iconData: Data?)
        case failure
    }

    private func finalize(hash: String, result: FetchResult) {
        guard var preview = try? LinkPreviewRepository.findPreview(byHash: hash) else { return }
        preview.fetchedAt = Date()
        if preview.hostname == nil {
            preview.hostname = URLNormalizer.normalizedHost(preview.url)
        }
        switch result {
        case .success(let title, let siteName, let summary, let imageData, let iconData):
            preview.title = title
            preview.siteName = siteName
            preview.summary = summary
            preview.imageData = imageData
            preview.iconData = iconData
            preview.status = (title == nil && summary == nil && imageData == nil && iconData == nil) ? .failed : .ok
        case .failure:
            preview.status = .failed
        }
        persist(preview)
    }

    private func markSkipped(_ rawURL: String) {
        let hash = URLNormalizer.hash(rawURL)
        if (try? LinkPreviewRepository.findPreview(byHash: hash)) != nil { return }
        persist(LinkPreviewRecord(
            urlHash: hash,
            url: URLNormalizer.normalize(rawURL),
            hostname: URLNormalizer.normalizedHost(rawURL),
            status: .skipped
        ))
    }

    private func persist(_ preview: LinkPreviewRecord) {
        try? LinkPreviewRepository.upsertPreview(preview)
        ClipboardStore.shared.upsertCachedPreview(preview)
    }
}
