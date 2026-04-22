import AppKit
import SwiftData
import SwiftUI

struct LinkPreviewCard: View {
    let rawURL: String

    @Query private var previews: [LinkPreview]

    init(rawURL: String) {
        self.rawURL = rawURL
        let hash = URLNormalizer.hash(rawURL)
        var fetch = FetchDescriptor<LinkPreview>(
            predicate: #Predicate { $0.urlHash == hash }
        )
        fetch.fetchLimit = 1
        _previews = Query(fetch)
    }

    private var preview: LinkPreview? { previews.first }
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
            if preview?.status != .ok {
                LinkPreviewService.shared.fetchIfNeeded(for: rawURL)
            }
        }
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
        let pending = preview?.status == .pending
        let failed = preview?.status == .failed
        let title = preview?.title ?? ""
        let summary = preview?.summary ?? ""
        let hasContent = !title.isEmpty || !summary.isEmpty || preview?.imageData != nil

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
                if let data = preview?.imageData, let nsImage = NSImage(data: data) {
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
        } else if pending {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Загружаем превью…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } else if failed {
            Text("Превью недоступно")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func siteHeader(_ site: String) -> some View {
        HStack(spacing: 6) {
            if let data = preview?.iconData, let nsImage = NSImage(data: data) {
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
