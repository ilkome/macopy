import AppKit
import SwiftUI

struct ItemRow: View {
    let model: RowModel
    var displayOverride: String? = nil
    var showBadge: Bool = true

    private var item: ClipboardItemRecord { model.item }
    private var selected: Bool { model.isSelected }

    private var renderedText: AttributedString {
        if let override = displayOverride {
            return AttributedString(override.replacingOccurrences(of: "\n", with: " "))
        }
        if let snippet = model.snippet {
            return snippet
        }
        let raw = item.preview.replacingOccurrences(of: "\n", with: " ")
        if item.kind == .url {
            return AttributedString(URLDisplay.stripScheme(raw))
        }
        return AttributedString(raw)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if showBadge {
                // Both subtrees stay in the tree; only opacity toggles. A structural if/else swap
                // here gets stuck in a LazyVStack row (lower rows keep the number after ⌘ is released).
                ZStack {
                    leadingBadge
                        .opacity(model.quickPasteNumber == nil ? 1 : 0)
                    Text(model.quickPasteNumber.map(String.init) ?? "")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 26, height: 26)
                        .opacity(model.quickPasteNumber == nil ? 0 : 1)
                }
            }
            textView
                .frame(maxWidth: .infinity, alignment: .leading)
            if let c = item.comment, !c.isEmpty {
                Image(systemName: "text.bubble")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(String(c.prefix(120)))
            }
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Layout.rowHeight)
        .background {
            Color.accentColor.opacity(selected ? 0.3 : 0)
        }
    }

    @ViewBuilder
    private var leadingBadge: some View {
        switch item.kind {
        case .image:
            if let path = item.imagePath {
                // .id(path) gives each image fresh @State so a reused row never shows the
                // previous item's thumbnail for a frame while the new one decodes off-main.
                ThumbnailBadge(filename: path).id(path)
            } else {
                badgeIcon(systemName: "photo")
            }
        case .color:
            RoundedRectangle(cornerRadius: 4)
                .fill(ColorParser.parse(item.text ?? "")?.color ?? .gray)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.secondary.opacity(0.3))
                )
        case .code:
            badgeIcon(systemName: "curlybraces")
        case .url:
            badgeIcon(systemName: "link")
        case .text:
            badgeIcon(systemName: "text.alignleft")
        }
    }

    private func badgeIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
    }

    @ViewBuilder
    private var textView: some View {
        switch item.kind {
        case .code:
            Text(renderedText)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
        case .color:
            Text(renderedText)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
        default:
            Text(renderedText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// Row image thumbnail. Renders a placeholder immediately and decodes the thumbnail off the
/// main thread (cache hit returns synchronously, so cached rows never flash the placeholder).
private struct ThumbnailBadge: View {
    let filename: String
    @State private var image: NSImage?

    var body: some View {
        content.task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 26, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "photo")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
        }
    }

    private func load() async {
        if let cached = ImageCache.cachedThumbnail(filename: filename) {
            image = cached
            return
        }
        let loaded = await ImageCache.loadThumbnail(filename: filename)
        guard !Task.isCancelled else { return }
        image = loaded
    }
}
