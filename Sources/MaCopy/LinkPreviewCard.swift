import AppKit
import SwiftUI

struct LinkPreviewCard: View {
    let rawURL: String

    @ObservedObject private var store = ClipboardStore.shared
    @State private var imageData: Data?
    @State private var iconData: Data?

    private var preview: LinkPreviewRecord? {
        store.previewsByHash[URLNormalizer.hash(rawURL)]
    }

    private var parsedURL: URL? { URL(string: rawURL) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                urlLink
                card
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: rawURL) {
            imageData = nil
            iconData = nil
            let hash = URLNormalizer.hash(rawURL)
            if store.previewsByHash[hash] == nil,
               let fromDb = try? LinkPreviewRepository.findPreview(byHash: hash) {
                store.upsertCachedPreview(fromDb)
            }
            if preview?.status != .ok {
                LinkPreviewService.shared.fetchIfNeeded(for: rawURL)
            }
            await loadBlobs()
        }
        .onChange(of: preview?.fetchedAt) {
            Task { await loadBlobs() }
        }
        .onChange(of: rawURL, initial: false) { oldURL, _ in
            LinkPreviewService.shared.cancel(rawURL: oldURL)
        }
    }

    /// The image/icon blobs live only in the DB now (stripped from the in-memory map to bound
    /// session memory), so the card loads them off-main into local state.
    private func loadBlobs() async {
        let hash = URLNormalizer.hash(rawURL)
        let record = await Task.detached(priority: .userInitiated) {
            try? LinkPreviewRepository.findPreview(byHash: hash)
        }.value
        guard hash == URLNormalizer.hash(rawURL) else { return }  // selection moved mid-load
        imageData = record?.imageData
        iconData = record?.iconData
    }

    @ViewBuilder
    private var urlLink: some View {
        if let url = parsedURL {
            Link(destination: url) {
                Text(rawURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.link)
                    .underline()
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
        } else {
            Text(rawURL)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var card: some View {
        let title = preview?.title ?? ""
        let summary = preview?.summary ?? ""
        let hasContent = !title.isEmpty || !summary.isEmpty || imageData != nil

        if hasContent {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    if let site = preview?.siteName, !site.isEmpty {
                        siteHeader(site)
                    }
                    if !title.isEmpty {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let data = imageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
    }

    private func siteHeader(_ site: String) -> some View {
        HStack(spacing: 6) {
            if let data = iconData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(site)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
