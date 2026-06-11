import SwiftUI

struct PreviewPane: View {
    let item: ClipboardItemRecord?

    // The list record carries only a capped text/ocr excerpt. Code preview and image
    // OCR may exceed it, so load the full record by id off-main; until it lands the
    // capped excerpt is shown. `.text` editing is handled inside TextBodyEditor.
    @State private var fullItem: ClipboardItemRecord?
    // Downsampled preview image, decoded off-main (full-res decode of a 5K screenshot
    // would freeze the main thread on every arrow-key move).
    @State private var previewImage: NSImage?

    private static let previewMaxPixel = 880
    private static let codePreviewCap = 10_000

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        if let item {
            content(for: item)
                .task(id: item.id) { await loadFullIfNeeded(item) }
        } else {
            placeholder
        }
    }

    private func loadFullIfNeeded(_ item: ClipboardItemRecord) async {
        previewImage = nil
        guard item.kind == .code || item.kind == .image else { return }
        let id = item.id

        if item.kind == .image, let path = item.imagePath {
            let maxPixel = Self.previewMaxPixel
            if let cached = ImageCache.clipboardPreviewCached(filename: path, maxPixelSize: maxPixel) {
                previewImage = cached
            } else if let decoded = await Task.detached(priority: .userInitiated, operation: {
                ImageCache.downsampledImage(filename: path, maxPixelSize: maxPixel)
            }).value {
                guard item.id == id else { return }
                ImageCache.storeClipboardPreview(decoded.image, filename: path, maxPixelSize: maxPixel)
                previewImage = decoded.image
            }
            guard item.id == id else { return }
        }

        let record = await Task.detached(priority: .userInitiated) {
            try? ClipboardItemRepository.findItem(byID: id)
        }.value
        guard item.id == id else { return }
        fullItem = record
    }

    /// Cap the rendered code preview: a SwiftUI Text in a ScrollView lays out the whole
    /// string, so a multi-MB clip freezes for seconds. O(cap), not O(text.count).
    private func cappedCode(_ text: String) -> String {
        if let end = text.index(text.startIndex, offsetBy: Self.codePreviewCap, limitedBy: text.endIndex),
           end < text.endIndex {
            return String(text[..<end]) + "\n\n… (truncated)"
        }
        return text
    }

    private func fullText(_ item: ClipboardItemRecord) -> String {
        if fullItem?.id == item.id, let t = fullItem?.text { return t }
        return item.text ?? item.preview
    }

    private func fullOCR(_ item: ClipboardItemRecord) -> String? {
        if fullItem?.id == item.id { return fullItem?.ocrText }
        return item.ocrText
    }

    private var placeholder: some View {
        VStack {
            Image(systemName: "square.and.pencil")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No preview")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for item: ClipboardItemRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            body(for: item)
            Spacer(minLength: 0)
            Divider().opacity(0.3)
            CommentEditor(item: item)
                .id(item.id)
            Divider().opacity(0.3)
            footer(for: item)
        }
    }

    @ViewBuilder
    private func body(for item: ClipboardItemRecord) -> some View {
        switch item.kind {
        case .image:
            imageBody(for: item)
        case .color:
            colorBody(for: item)
        case .code:
            textBody(cappedCode(fullText(item)), monospaced: true)
        case .url:
            urlBody(for: item)
        case .text:
            TextBodyEditor(item: item).id(item.id)
        }
    }

    private func textBody(_ text: String, monospaced: Bool) -> some View {
        ScrollView {
            Text(text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    private func urlBody(for item: ClipboardItemRecord) -> some View {
        let raw = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        return LinkPreviewCard(rawURL: raw)
    }

    private func imageBody(for item: ClipboardItemRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 220)
                    .overlay(ProgressView().controlSize(.small))
            }
            if item.imageWidth > 0 {
                Text("\(item.imageWidth) × \(item.imageHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let ocr = fullOCR(item), !ocr.isEmpty {
                Divider().opacity(0.3)
                Text("OCR")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ScrollView {
                    Text(ocr)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
            }
        }
        .padding(12)
    }

    private func colorBody(for item: ClipboardItemRecord) -> some View {
        let raw = item.text ?? item.preview
        let parsed = ColorParser.parse(raw)
        return VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(parsed?.color ?? .gray)
                .frame(height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.secondary.opacity(0.3))
                )
            Text(raw)
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
            if let rgb = parsed?.rgbString {
                Text(rgb)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
    }

    private func footer(for item: ClipboardItemRecord) -> some View {
        HStack(spacing: 8) {
            if let path = item.sourceAppIconPath,
               let img = ImageCache.appIcon(filename: path) {
                Image(nsImage: img).resizable().scaledToFit().frame(width: 16, height: 16)
            }
            Text(item.sourceAppName ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("·").foregroundStyle(.tertiary).font(.caption2)
            Text(Self.relativeFormatter.localizedString(for: item.updatedAt, relativeTo: Date()))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("·").foregroundStyle(.tertiary).font(.caption2)
            Text(byteString(item.byteSize))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
            if item.kind == .url {
                Button {
                    let raw = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
                    LinkPreviewService.shared.fetchIfNeeded(for: raw, force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Refresh preview")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
