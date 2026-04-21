import AppKit
import Fuse
import SwiftData
import SwiftUI

enum Layout {
    static let rowHeight: CGFloat = 48
    static let visibleRows = 9
    static let searchHeight: CGFloat = 44
    static let tabsHeight: CGFloat = 36
    static let defaultListWidth: CGFloat = 380
    static let defaultPreviewWidth: CGFloat = 360
    static let splitDividerWidth: CGFloat = 6
    static let minListWidth: CGFloat = 260
    static let minPreviewWidth: CGFloat = 240
    static var panelWidth: CGFloat {
        defaultListWidth + splitDividerWidth + defaultPreviewWidth
    }
    static var maxListWidth: CGFloat {
        panelWidth - splitDividerWidth - minPreviewWidth
    }
    static var listHeight: CGFloat { rowHeight * CGFloat(visibleRows) }
    static var panelHeight: CGFloat {
        searchHeight + 1 + tabsHeight + 1 + listHeight
    }
}

enum Tab: Int, CaseIterable {
    case all, favorites, images, urls, colors, code

    var title: String {
        switch self {
        case .all: "Все"
        case .favorites: "Избранное"
        case .images: "Изображения"
        case .urls: "Ссылки"
        case .colors: "Цвета"
        case .code: "Код"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: true
        case .favorites: item.isFavorite
        case .images: item.kind == .image
        case .urls: item.kind == .url
        case .colors: item.kind == .color
        case .code: item.kind == .code
        }
    }
}

@MainActor
private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

struct ContentView: View {
    @Environment(\.modelContext) private var ctx
    @Query(ContentView.recentDescriptor) private var allItems: [ClipboardItem]

    private static var recentDescriptor: FetchDescriptor<ClipboardItem> {
        var d = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.updatedAt, order: .reverse)]
        )
        d.fetchLimit = 2000
        return d
    }

    @State private var query: String = ""
    @State private var selection: UUID?
    @State private var tab: Tab = .all
    @AppStorage("listWidth") private var listWidth: Double = Double(Layout.defaultListWidth)
    @FocusState private var searchFocused: Bool

    @State private var rows: [RowModel] = []
    @State private var sections: [Section] = []
    @State private var rowsById: [UUID: RowModel] = [:]
    @State private var minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var searchTask: Task<Void, Never>?
    @ObservedObject private var settings = AppSettings.shared

    private var selectedItem: ClipboardItem? {
        selection.flatMap { rowsById[$0]?.item }
    }

    @Observable
    final class RowModel: Identifiable {
        let item: ClipboardItem
        var match: SearchMatch?
        var isSelected: Bool = false

        var id: UUID { item.id }

        init(item: ClipboardItem, match: SearchMatch? = nil) {
            self.item = item
            self.match = match
        }
    }

    struct Section: Identifiable {
        let id: Int
        let title: String
        let rows: [RowModel]
    }

    struct SearchMatch: Equatable {
        let score: Double
        let snippet: AttributedString
    }

    private struct AllItemsSignature: Equatable {
        let count: Int
        let topUpdatedAt: Date?
    }

    private var allItemsSignature: AllItemsSignature {
        AllItemsSignature(count: allItems.count, topUpdatedAt: allItems.first?.updatedAt)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                searchField(proxy: proxy)
                    .frame(height: Layout.searchHeight)
                Divider().opacity(0.3)
                tabBar
                    .frame(height: Layout.tabsHeight)
                Divider().opacity(0.3)
                HStack(spacing: 0) {
                    listView(proxy: proxy)
                        .frame(width: CGFloat(listWidth))
                    ResizableDivider(
                        width: $listWidth,
                        minWidth: Double(Layout.minListWidth),
                        maxWidth: Double(Layout.maxListWidth)
                    )
                    .frame(width: Layout.splitDividerWidth)
                    PreviewPane(item: selectedItem)
                        .frame(
                            width: Layout.panelWidth
                                - CGFloat(listWidth)
                                - Layout.splitDividerWidth
                        )
                }
                .frame(height: Layout.listHeight)
            }
            .onReceive(NotificationCenter.default.publisher(for: .clipboardPanelReset)) { _ in
                resetToTop(proxy: proxy)
            }
            .onChange(of: tab) { _, _ in
                recompute(forceFirst: true)
                if let firstSection = sections.first {
                    proxy.scrollTo("section-\(firstSection.id)", anchor: .top)
                }
            }
            .onChange(of: query) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled else { return }
                    let list = recompute(forceFirst: true)
                    if !list.isEmpty, let firstSection = sections.first {
                        proxy.scrollTo("section-\(firstSection.id)", anchor: .top)
                    }
                }
            }
            .onChange(of: allItemsSignature) { _, _ in
                recompute()
            }
            .onReceive(minuteTick) { _ in
                sections = buildSections(rows, query: query)
            }
        }
        .frame(width: Layout.panelWidth, height: Layout.panelHeight)
        .background(settings.panelMaterial.material)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transaction { $0.animation = nil }
        .onAppear {
            recompute()
            searchFocused = true
        }
    }

    @discardableResult
    private func recompute(forceFirst: Bool = false) -> [RowModel] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousById = rowsById

        func reuseOrCreate(item: ClipboardItem, match: SearchMatch?) -> RowModel {
            if let existing = previousById[item.id] {
                if existing.match != match {
                    existing.match = match
                }
                return existing
            }
            return RowModel(item: item, match: match)
        }

        let built: [RowModel]
        if q.isEmpty {
            built = allItems
                .filter { tab.matches($0) }
                .map { reuseOrCreate(item: $0, match: nil) }
        } else {
            let fuse = Fuse(location: 0, distance: 1_000_000, threshold: 0.4)
            guard let pattern = fuse.createPattern(from: q) else {
                rows = []
                sections = []
                rowsById = [:]
                selection = nil
                return []
            }
            var scored: [(ClipboardItem, Double, AttributedString)] = []
            for item in allItems where tab.matches(item) {
                let fields: [String?] = [item.text, item.ocrText, item.preview, item.sourceAppName]
                var bestScore: Double?
                var bestField: String?
                var bestRanges: [CountableClosedRange<Int>] = []
                for field in fields {
                    guard let field, !field.isEmpty else { continue }
                    guard let r = fuse.search(pattern, in: field) else { continue }
                    if bestScore == nil || r.score < bestScore! {
                        bestScore = r.score
                        bestField = field
                        bestRanges = r.ranges
                    }
                }
                if let s = bestScore, let field = bestField, !bestRanges.isEmpty {
                    let snippet = SearchSnippet.build(text: field, ranges: bestRanges, radius: 40)
                    scored.append((item, s, snippet))
                }
            }
            scored.sort { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.0.updatedAt != rhs.0.updatedAt { return lhs.0.updatedAt > rhs.0.updatedAt }
                return lhs.0.id.uuidString < rhs.0.id.uuidString
            }
            built = scored.map { item, score, snippet in
                reuseOrCreate(item: item, match: SearchMatch(score: score, snippet: snippet))
            }
        }
        let newSections = buildSections(built, query: q)
        let newById = Dictionary(uniqueKeysWithValues: built.map { ($0.id, $0) })
        rows = built
        sections = newSections
        rowsById = newById
        let newSelection: UUID?
        if forceFirst {
            newSelection = built.first?.id
        } else if let sel = selection, newById[sel] != nil {
            newSelection = sel
        } else {
            newSelection = built.first?.id
        }
        applySelection(newSelection)
        return built
    }

    private func applySelection(_ newId: UUID?) {
        guard selection != newId else { return }
        if let oldId = selection,
           let oldModel = rowsById[oldId],
           oldModel.isSelected {
            oldModel.isSelected = false
        }
        selection = newId
        if let newId,
           let newModel = rowsById[newId],
           !newModel.isSelected {
            newModel.isSelected = true
        }
    }

    private func buildSections(_ list: [RowModel], query: String) -> [Section] {
        guard !list.isEmpty else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return [Section(id: 0, title: "Результаты", rows: list)]
        }
        let now = Date()
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)

        func bucket(_ date: Date) -> Int {
            if now.timeIntervalSince(date) <= 3600 { return 0 }
            if cal.isDate(date, inSameDayAs: now) { return 1 }
            if let y = yesterday, cal.isDate(date, inSameDayAs: y) { return 2 }
            if cal.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return 3 }
            return 4
        }

        let titles = [
            "В течение часа",
            "Сегодня",
            "Вчера",
            "На этой неделе",
            "Ранее"
        ]

        var groups: [Int: [RowModel]] = [:]
        for row in list {
            groups[bucket(row.item.updatedAt), default: []].append(row)
        }
        return (0..<titles.count).compactMap { i in
            guard let arr = groups[i], !arr.isEmpty else { return nil }
            return Section(id: i, title: titles[i], rows: arr)
        }
    }

    private func resetToTop(proxy: ScrollViewProxy) {
        query = ""
        tab = .all
        searchFocused = true
        recompute(forceFirst: true)
        if let first = sections.first {
            proxy.scrollTo("section-\(first.id)", anchor: .top)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.rawValue) { t in
                tabChip(t)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private func tabChip(_ t: Tab) -> some View {
        let active = t == tab
        return Text(t.title)
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                active
                    ? Color.accentColor.opacity(0.35)
                    : Color.secondary.opacity(0.12)
            )
            .foregroundStyle(active ? Color.primary : .secondary)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture { tab = t }
    }

    private func cycleTab(_ delta: Int) {
        let cases = Tab.allCases
        let idx = cases.firstIndex(of: tab) ?? 0
        let count = cases.count
        let next = ((idx + delta) % count + count) % count
        tab = cases[next]
    }

    private func searchField(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            TextField("Поиск", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
                .onKeyPress(.escape) {
                    AppDelegate.shared?.hidePanel()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    move(1, proxy: proxy)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    move(-1, proxy: proxy)
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    guard query.isEmpty else { return .ignored }
                    cycleTab(-1)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    guard query.isEmpty else { return .ignored }
                    cycleTab(1)
                    return .handled
                }
                .onKeyPress(.return) {
                    paste()
                    return .handled
                }
                .onKeyPress(keys: ["d"]) { press in
                    if press.modifiers.contains(.command) {
                        toggleFavorite()
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(keys: [.delete, .deleteForward]) { press in
                    if press.modifiers.contains(.command) {
                        deleteSelected()
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.space) {
                    guard let item = selectedItem,
                          item.kind == .image,
                          let path = item.imagePath
                    else { return .ignored }
                    QuickLookController.shared.toggle(url: Storage.imageURL(for: path))
                    return .handled
                }
            Text("⌘4")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            settingsMenu
        }
        .padding(.horizontal, 18)
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("OCR для скриншотов", isOn: $settings.ocrEnabled)
            Picker("Плотность фона", selection: $settings.panelMaterial) {
                ForEach(PanelMaterial.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Divider()
            Button("Выход") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func listView(proxy: ScrollViewProxy) -> some View {
        let groups = sections
        return ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                if groups.isEmpty {
                    emptyState
                } else {
                    ForEach(groups) { section in
                        sectionHeader(section.title)
                            .id("section-\(section.id)")
                        ForEach(section.rows) { row in
                            ItemRow(model: row)
                                .id(row.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { paste(row.item) }
                                .simultaneousGesture(
                                    TapGesture().onEnded { applySelection(row.id) }
                                )
                        }
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
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

    private func move(_ delta: Int, proxy: ScrollViewProxy) {
        let list = rows
        guard !list.isEmpty else { return }
        let idx = list.firstIndex(where: { $0.id == selection }) ?? 0
        let new = max(0, min(list.count - 1, idx + delta))
        let newId = list[new].id
        guard newId != selection else { return }
        applySelection(newId)
        if let section = sections.first(where: { $0.rows.first?.id == newId }) {
            proxy.scrollTo("section-\(section.id)", anchor: .top)
        } else {
            proxy.scrollTo(newId, anchor: nil)
        }
    }

    private func paste(_ override: ClipboardItem? = nil) {
        guard let target = override ?? selection.flatMap({ rowsById[$0]?.item }) else { return }
        if !Paster.shared.paste(target) {
            removeItem(target)
        }
    }

    private func deleteSelected() {
        guard let sel = selection, let row = rowsById[sel] else { return }
        removeItem(row.item)
    }

    private func toggleFavorite() {
        guard let sel = selection, let row = rowsById[sel] else { return }
        row.item.isFavorite.toggle()
        try? ctx.save()
        recompute()
    }

    private func removeItem(_ item: ClipboardItem) {
        if let path = item.imagePath {
            let url = Storage.imageURL(for: path)
            ImageCache.invalidate(url)
            try? FileManager.default.removeItem(at: url)
        }
        ctx.delete(item)
        try? ctx.save()
        recompute()
    }
}

struct ItemRow: View {
    @Bindable var model: ContentView.RowModel

    private var item: ClipboardItem { model.item }
    private var match: ContentView.SearchMatch? { model.match }
    private var selected: Bool { model.isSelected }

    private var renderedText: AttributedString {
        if let snippet = match?.snippet {
            return snippet
        }
        return AttributedString(item.preview.replacingOccurrences(of: "\n", with: " "))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            sourceIcon
            content
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                kindBadge
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Layout.rowHeight)
        .background {
            Color.accentColor.opacity(selected ? 0.3 : 0)
        }
    }

    private var sourceIcon: some View {
        Group {
            if let path = item.sourceAppIconPath,
               let image = ImageCache.image(at: Storage.iconURL(for: path)) {
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
            Text(renderedText)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
        case .url:
            Text(renderedText)
                .lineLimit(1)
                .truncationMode(.middle)
        default:
            Text(renderedText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var imageContent: some View {
        HStack(spacing: 10) {
            if let path = item.imagePath,
               let image = ImageCache.thumbnail(at: Storage.imageURL(for: path), maxPixelSize: 88) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text(renderedText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var colorContent: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(ColorParser.parse(item.text ?? "")?.color ?? .gray)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.secondary.opacity(0.3))
                )
            Text(renderedText)
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

}

struct ResizableDivider: NSViewRepresentable {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double

    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        view.onDelta = { delta in
            let next = width + Double(delta)
            width = min(maxWidth, max(minWidth, next))
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? DragView else { return }
        v.onDelta = { delta in
            let next = width + Double(delta)
            width = min(maxWidth, max(minWidth, next))
        }
    }

    private final class DragView: NSView {
        var onDelta: ((CGFloat) -> Void)?
        private var tracking: NSTrackingArea?

        override var mouseDownCanMoveWindow: Bool { false }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tracking = area
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseEntered(with event: NSEvent) {
            NSCursor.resizeLeftRight.set()
        }

        override func mouseExited(with event: NSEvent) {
            NSCursor.arrow.set()
        }

        override func mouseDown(with event: NSEvent) {}

        override func mouseDragged(with event: NSEvent) {
            onDelta?(event.deltaX)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()
        }
    }
}

struct PreviewPane: View {
    let item: ClipboardItem?

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
    private func content(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(for: item)
            Divider().opacity(0.3)
            body(for: item)
            Spacer(minLength: 0)
            footer(for: item)
        }
    }

    private func header(for item: ClipboardItem) -> some View {
        HStack(spacing: 8) {
            if let path = item.sourceAppIconPath,
               let img = ImageCache.image(at: Storage.iconURL(for: path)) {
                Image(nsImage: img).resizable().scaledToFit().frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.sourceAppName ?? "—")
                    .font(.caption)
                    .lineLimit(1)
                Text(relativeFormatter.localizedString(for: item.updatedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func body(for item: ClipboardItem) -> some View {
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

    private func urlBody(for item: ClipboardItem) -> some View {
        let raw = item.text ?? item.preview
        return VStack(alignment: .leading, spacing: 8) {
            if let url = URL(string: raw) {
                Link(destination: url) {
                    Text(raw)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.link)
                        .underline()
                }
                .buttonStyle(.plain)
                if let host = url.host {
                    Text(host).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(raw).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func imageBody(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let path = item.imagePath,
               let image = ImageCache.image(at: Storage.imageURL(for: path)) {
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

    private func colorBody(for item: ClipboardItem) -> some View {
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

    private func footer(for item: ClipboardItem) -> some View {
        HStack(spacing: 12) {
            Text(byteString(item.byteSize))
            if let path = item.sourceFilePath {
                Text("•").foregroundStyle(.tertiary)
                Text(path).truncationMode(.middle).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
