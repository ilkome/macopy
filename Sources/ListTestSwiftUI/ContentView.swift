import AppKit
import SwiftData
import SwiftUI

enum Layout {
    static let rowHeight: CGFloat = 48
    static let visibleRows = 9
    static let searchHeight: CGFloat = 44
    static let panelWidth: CGFloat = 560
    static var listHeight: CGFloat { rowHeight * CGFloat(visibleRows) }
    static var panelHeight: CGFloat { searchHeight + 1 + listHeight }
}

struct ContentView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \ClipboardItem.updatedAt, order: .reverse) private var allItems: [ClipboardItem]

    @State private var query: String = ""
    @State private var selection: UUID?
    @FocusState private var searchFocused: Bool

    private var items: [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allItems }
        return allItems.filter { item in
            if item.preview.lowercased().contains(q) { return true }
            if let t = item.text?.lowercased(), t.contains(q) { return true }
            if let o = item.ocrText?.lowercased(), o.contains(q) { return true }
            if let n = item.sourceAppName?.lowercased(), n.contains(q) { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .frame(height: Layout.searchHeight)
            Divider().opacity(0.3)
            listView
                .frame(height: Layout.listHeight)
        }
        .frame(width: Layout.panelWidth, height: Layout.panelHeight)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            searchFocused = true
            pickInitial()
        }
        .onChange(of: query) { _, _ in pickInitial() }
        .onChange(of: items.map(\.id)) { _, _ in pickInitial() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Поиск", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(.escape) {
                    AppDelegate.shared?.hidePanel()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    move(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    move(-1)
                    return .handled
                }
                .onKeyPress(.return) {
                    paste()
                    return .handled
                }
                .onKeyPress(keys: [.delete, .deleteForward]) { press in
                    if press.modifiers.contains(.command) {
                        deleteSelected()
                        return .handled
                    }
                    return .ignored
                }
            Text("⌘4")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12)
    }

    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(items) { item in
                            ItemRow(item: item, selected: selection == item.id)
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { paste(item) }
                                .onTapGesture { selection = item.id }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: selection) { _, new in
                guard let new else { return }
                proxy.scrollTo(new, anchor: nil)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "История пуста" : "Ничего не найдено")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func pickInitial() {
        if selection == nil || !items.contains(where: { $0.id == selection }) {
            selection = items.first?.id
        }
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        let idx = items.firstIndex(where: { $0.id == selection }) ?? 0
        let new = max(0, min(items.count - 1, idx + delta))
        selection = items[new].id
    }

    private func paste(_ override: ClipboardItem? = nil) {
        guard let target = override ?? items.first(where: { $0.id == selection }) else { return }
        let ok = Paster.paste(target)
        if !ok {
            removeItem(target)
        }
    }

    private func deleteSelected() {
        guard let sel = items.first(where: { $0.id == selection }) else { return }
        removeItem(sel)
    }

    private func removeItem(_ item: ClipboardItem) {
        if let path = item.imagePath {
            try? FileManager.default.removeItem(at: Storage.imageURL(for: path))
        }
        ctx.delete(item)
        try? ctx.save()
    }
}

struct ItemRow: View {
    let item: ClipboardItem
    let selected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            sourceIcon
            content
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                kindBadge
                Text(timeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Layout.rowHeight)
        .background(
            selected
                ? Color.accentColor.opacity(0.3)
                : Color.clear
        )
    }

    private var sourceIcon: some View {
        Group {
            if let path = item.sourceAppIconPath,
               let image = NSImage(contentsOf: Storage.iconURL(for: path)) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .scaledToFit()
        .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            imageContent
        case .color:
            colorContent
        case .code:
            Text(item.preview.replacingOccurrences(of: "\n", with: " "))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
        case .url:
            Text(item.preview)
                .lineLimit(1)
                .foregroundStyle(.blue)
                .truncationMode(.middle)
        default:
            Text(item.preview.replacingOccurrences(of: "\n", with: " "))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var imageContent: some View {
        HStack(spacing: 10) {
            if let path = item.imagePath,
               let image = NSImage(contentsOf: Storage.imageURL(for: path)) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text(item.preview)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var colorContent: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(colorFromString(item.text ?? "") ?? .gray)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.secondary.opacity(0.3))
                )
            Text(item.preview)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
        }
    }

    private var kindBadge: some View {
        Text(kindLabel)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(kindColor.opacity(0.25))
            .foregroundStyle(kindColor)
            .clipShape(Capsule())
    }

    private var kindLabel: String {
        switch item.kind {
        case .text: "TEXT"
        case .code: "CODE"
        case .url: "URL"
        case .color: "COLOR"
        case .image: "IMG"
        }
    }

    private var kindColor: Color {
        switch item.kind {
        case .text: .gray
        case .code: .purple
        case .url: .blue
        case .color: .orange
        case .image: .green
        }
    }

    private var timeLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.updatedAt, relativeTo: Date())
    }
}

private func colorFromString(_ input: String) -> Color? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    var str = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    if [3, 4].contains(str.count) {
        str = str.map { "\($0)\($0)" }.joined()
    }
    guard let value = UInt64(str, radix: 16) else { return nil }
    let r, g, b, a: Double
    if str.count == 6 {
        r = Double((value >> 16) & 0xff) / 255
        g = Double((value >> 8) & 0xff) / 255
        b = Double(value & 0xff) / 255
        a = 1
    } else if str.count == 8 {
        r = Double((value >> 24) & 0xff) / 255
        g = Double((value >> 16) & 0xff) / 255
        b = Double((value >> 8) & 0xff) / 255
        a = Double(value & 0xff) / 255
    } else {
        return nil
    }
    return Color(red: r, green: g, blue: b, opacity: a)
}
