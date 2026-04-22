import AppKit
@preconcurrency import LinkPresentation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class LinkPreviewService {
    static let shared = LinkPreviewService()

    private var inFlight: Set<String> = []

    private init() {}

    func fetchIfNeeded(for rawURL: String, force: Bool = false) {
        guard AppSettings.shared.linkPreviewsEnabled else { return }
        guard URLNormalizer.shouldFetchPreview(rawURL) else {
            markSkipped(rawURL)
            return
        }
        let hash = URLNormalizer.hash(rawURL)
        if inFlight.contains(hash) { return }

        let ctx = Storage.container.mainContext
        if let existing = Self.find(hash: hash, ctx: ctx) {
            if !force && existing.status == .ok { return }
            if !force,
               existing.status == .failed,
               Date().timeIntervalSince(existing.fetchedAt) < 30 {
                return
            }
            existing.status = .pending
            try? ctx.save()
        } else {
            let preview = LinkPreview(
                urlHash: hash,
                url: URLNormalizer.normalize(rawURL),
                hostname: URLNormalizer.normalizedHost(rawURL),
                status: .pending
            )
            ctx.insert(preview)
            try? ctx.save()
        }

        inFlight.insert(hash)
        Task { await self.fetch(rawURL: rawURL, hash: hash) }
    }

    func backfillPending() {
        guard AppSettings.shared.linkPreviewsEnabled else { return }
        let ctx = Storage.container.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.kindRaw == "url" }
        )
        guard let urlItems = try? ctx.fetch(descriptor) else { return }
        for item in urlItems {
            let raw = item.text ?? item.preview
            guard !raw.isEmpty else { continue }
            let hash = URLNormalizer.hash(raw)
            if Self.find(hash: hash, ctx: ctx) == nil {
                fetchIfNeeded(for: raw)
            }
        }
    }

    private func fetch(rawURL: String, hash: String) async {
        defer { inFlight.remove(hash) }
        guard let url = URLNormalizer.parse(rawURL) else {
            finalize(hash: hash, result: .failure)
            return
        }

        async let ogTask = OpenGraphParser.fetch(url: url)
        async let lpTask = Self.fetchLPMetadata(for: url)
        let og = await ogTask
        let lp = await lpTask

        let title = og?.title ?? lp?.title
        let summary = og?.description
        let siteName = og?.siteName ?? lp?.url?.host ?? lp?.originalURL?.host ?? url.host

        var imageData: Data?
        if let ogImage = og?.imageURL {
            imageData = await Self.downloadImage(from: ogImage)
        }
        if imageData == nil, let provider = lp?.imageProvider {
            imageData = await Self.loadImage(from: provider)
        }
        let iconData = await Self.loadImage(from: lp?.iconProvider)

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
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode)
        else { return nil }
        return encodePNG(data: data)
    }

    private enum FetchResult {
        case success(title: String?, siteName: String?, summary: String?, imageData: Data?, iconData: Data?)
        case failure
    }

    private func finalize(hash: String, result: FetchResult) {
        let ctx = Storage.container.mainContext
        guard let preview = Self.find(hash: hash, ctx: ctx) else { return }
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
        try? ctx.save()
    }

    private func markSkipped(_ rawURL: String) {
        let hash = URLNormalizer.hash(rawURL)
        let ctx = Storage.container.mainContext
        if Self.find(hash: hash, ctx: ctx) != nil { return }
        let preview = LinkPreview(
            urlHash: hash,
            url: URLNormalizer.normalize(rawURL),
            hostname: URLNormalizer.normalizedHost(rawURL),
            status: .skipped
        )
        ctx.insert(preview)
        try? ctx.save()
    }

    private nonisolated static func loadImage(from provider: NSItemProvider?) async -> Data? {
        guard let provider else { return nil }
        let ids = provider.registeredTypeIdentifiers
        let imageIDs = ids.filter { UTType($0)?.conforms(to: .image) == true }
        let ordered = imageIDs.isEmpty ? ids : imageIDs
        for id in ordered {
            if let data = await loadData(from: provider, typeIdentifier: id),
               let normalized = encodePNG(data: data) {
                return normalized
            }
        }
        if let tiff = await loadNSImageData(from: provider),
           let data = encodePNG(data: tiff) {
            return data
        }
        return nil
    }

    private nonisolated static func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                cont.resume(returning: data)
            }
        }
    }

    private nonisolated static func loadNSImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage,
                      let tiff = image.tiffRepresentation
                else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: tiff)
            }
        }
    }

    private nonisolated static func encodePNG(data: Data, maxDimension: CGFloat = 800) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    static func find(hash: String, ctx: ModelContext) -> LinkPreview? {
        let needle = hash
        var fetch = FetchDescriptor<LinkPreview>(
            predicate: #Predicate { $0.urlHash == needle }
        )
        fetch.fetchLimit = 1
        return try? ctx.fetch(fetch).first
    }

    static func delete(urlHash: String, ctx: ModelContext) {
        guard let preview = find(hash: urlHash, ctx: ctx) else { return }
        ctx.delete(preview)
        try? ctx.save()
    }
}
