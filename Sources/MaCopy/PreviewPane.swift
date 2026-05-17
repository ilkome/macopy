import SwiftUI

struct PreviewPane: View {
    let item: ClipboardItemRecord?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        if let item {
            content(for: item)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack {
            Image(systemName: "square.and.pencil")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Нет превью")
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
            textBody(item.text ?? item.preview, monospaced: true)
        case .url:
            urlBody(for: item)
        default:
            textBody(item.text ?? item.preview, monospaced: false)
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
            if let path = item.imagePath,
               let image = ImageCache.clipboardImage(filename: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if item.imageWidth > 0 {
                Text("\(item.imageWidth) × \(item.imageHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let ocr = item.ocrText, !ocr.isEmpty {
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
                .help("Обновить превью")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
