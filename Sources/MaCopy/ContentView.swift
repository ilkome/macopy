import AppKit
import Fuse
import KeyboardShortcuts
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

    static let defaultDomainsWidth: CGFloat = 180
    static let defaultUrlListWidth: CGFloat = 300
    static let minDomainsWidth: CGFloat = 120
    static let minUrlListWidth: CGFloat = 180
    static let minUrlPreviewWidth: CGFloat = 200

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

    static var urlMaxDomainsWidth: CGFloat {
        panelWidth - splitDividerWidth * 2 - minUrlListWidth - minUrlPreviewWidth
    }
    static func urlMaxListWidth(domains: CGFloat) -> CGFloat {
        panelWidth - splitDividerWidth * 2 - domains - minUrlPreviewWidth
    }
    static func urlPreviewWidth(domains: CGFloat, list: CGFloat) -> CGFloat {
        max(
            minUrlPreviewWidth,
            panelWidth - splitDividerWidth * 2 - domains - list
        )
    }
}

enum Tab: Int, CaseIterable {
    case favorites, all, urls, images, colors, code

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

private let otherDomainKey = "__other__"
private let domainSectionPrefix = "domain-"

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
    @State private var selection: Selectable?
    @State private var tab: Tab = .all
    @AppStorage("listWidth") private var listWidth: Double = Double(Layout.defaultListWidth)
    @AppStorage("urlDomainsWidth") private var urlDomainsWidth: Double = Double(Layout.defaultDomainsWidth)
    @AppStorage("urlListWidth") private var urlListWidth: Double = Double(Layout.defaultUrlListWidth)
    @FocusState private var searchFocused: Bool

    @State private var rows: [RowModel] = []
    @State private var sections: [Section] = []
    @State private var rowsById: [UUID: RowModel] = [:]
    @State private var domainByItemID: [UUID: String] = [:]
    @State private var domainSectionsCache: [Section] = []
    @State private var sectionsByID: [String: Section] = [:]
    @State private var firstRowSectionID: [UUID: String] = [:]
    @State private var visibleListCache: [Selectable] = []
    @State private var minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var searchTask: Task<Void, Never>?
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var uiState = UIState.shared
    @State private var keyMonitor: Any?

    enum Selectable: Hashable {
        case item(UUID)
        case domain(String)

        var scrollID: String {
            switch self {
            case .item(let id): return id.uuidString
            case .domain(let name): return domainSectionPrefix + name
            }
        }
    }

    private var selectedItem: ClipboardItem? {
        guard case let .item(id) = selection else { return nil }
        return rowsById[id]?.item
    }

    private var previewItem: ClipboardItem? {
        switch selection {
        case .item(let id):
            return rowsById[id]?.item
        case .domain(let name):
            return sectionsByID[domainSectionPrefix + name]?.rows.first?.item
        case .none:
            return nil
        }
    }

    private var urlMode: Bool {
        tab == .urls && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var togglePanelShortcutLabel: String? {
        KeyboardShortcuts.getShortcut(for: .togglePanel).map { "\($0)" }
    }

    private var currentDomainName: String? {
        switch selection {
        case .domain(let name): return name
        case .item(let id): return domainByItemID[id]
        case .none: return nil
        }
    }

    private var currentDomainRows: [RowModel] {
        guard let name = currentDomainName else { return [] }
        return sectionsByID[domainSectionPrefix + name]?.rows ?? []
    }

    private var domainSections: [Section] {
        domainSectionsCache
    }

    @Observable
    final class RowModel: Identifiable {
        let item: ClipboardItem
        var match: SearchMatch?
        var isSelected: Bool = false

        var id: UUID { item.id }

        private var _parsedURL: URL??
        var parsedURL: URL? {
            if let cached = _parsedURL { return cached }
            let raw = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
            var url = URL(string: raw)
            if url == nil,
               let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                url = URL(string: encoded)
            }
            _parsedURL = url
            return url
        }

        init(item: ClipboardItem, match: SearchMatch? = nil) {
            self.item = item
            self.match = match
        }
    }

    struct Section: Identifiable {
        let id: String
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

    private struct ScoringInput: Sendable {
        let id: UUID
        let updatedAt: Date
        let fields: [String]
    }

    private struct ScoredResult: Sendable {
        let id: UUID
        let score: Double
        let snippet: AttributedString
    }

    private var allItemsSignature: AllItemsSignature {
        AllItemsSignature(count: allItems.count, topUpdatedAt: allItems.first?.updatedAt)
    }

    var body: some View {
        Group {
            if uiState.showSettings {
                SettingsView(onBack: { uiState.showSettings = false })
            } else {
                mainBody
            }
        }
        .frame(width: Layout.panelWidth, height: Layout.panelHeight)
        .background(settings.panelMaterial.material)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transaction { $0.animation = nil }
        .onAppear {
            clampPersistedWidths()
            searchFocused = true
            kickRecompute(forceFirst: false, debounce: false)
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: uiState.showSettings) { _, isSettings in
            if !isSettings {
                DispatchQueue.main.async { searchFocused = true }
            }
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handlePanelKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func handlePanelKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.contains(.command) else { return event }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 2:
            toggleFavorite()
            return nil
        case 14:
            guard case .item = selection else { return event }
            uiState.commentFocusToken &+= 1
            return nil
        case 51, 117:
            if let text = NSApp.keyWindow?.firstResponder as? NSText,
               !text.string.isEmpty {
                return event
            }
            deleteSelected()
            return nil
        case 0:
            return forwardAction(Selector("selectAll:"), event: event)
        case 8:
            return forwardAction(Selector("copy:"), event: event)
        case 9:
            return forwardAction(Selector("paste:"), event: event)
        case 7:
            return forwardAction(Selector("cut:"), event: event)
        case 6:
            return forwardAction(Selector(shift ? "redo:" : "undo:"), event: event)
        default:
            return event
        }
    }

    private func forwardAction(_ selector: Selector, event: NSEvent) -> NSEvent? {
        if NSApp.sendAction(selector, to: nil, from: nil) {
            return nil
        }
        return event
    }

    private var mainBody: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                searchField(proxy: proxy)
                    .frame(height: Layout.searchHeight)
                Divider().opacity(0.3)
                tabBar
                    .frame(height: Layout.tabsHeight)
                Divider().opacity(0.3)
                if urlMode {
                    urlThreePane(proxy: proxy)
                        .frame(height: Layout.listHeight)
                } else {
                    HStack(spacing: 0) {
                        listView(proxy: proxy)
                            .frame(width: CGFloat(listWidth))
                        ResizableDivider(
                            width: $listWidth,
                            minWidth: Double(Layout.minListWidth),
                            maxWidth: Double(Layout.maxListWidth)
                        )
                        .frame(width: Layout.splitDividerWidth)
                        PreviewPane(item: previewItem)
                            .frame(
                                width: Layout.panelWidth
                                    - CGFloat(listWidth)
                                    - Layout.splitDividerWidth
                            )
                    }
                    .frame(height: Layout.listHeight)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .clipboardPanelReset)) { _ in
                resetToTop(proxy: proxy)
            }
            .onChange(of: tab) { _, _ in
                kickRecompute(forceFirst: true, debounce: false) {
                    if let firstSection = sections.first {
                        proxy.scrollTo("section-\(firstSection.id)", anchor: .top)
                    }
                }
            }
            .onChange(of: query) { _, _ in
                kickRecompute(forceFirst: true, debounce: false) {
                    if !sections.isEmpty, let firstSection = sections.first {
                        proxy.scrollTo("section-\(firstSection.id)", anchor: .top)
                    }
                }
            }
            .onChange(of: allItemsSignature) { _, _ in
                kickRecompute(forceFirst: false, debounce: false)
            }
            .onReceive(minuteTick) { _ in
                sections = buildSections(rows, query: query)
            }
        }
    }

    private func clampPersistedWidths() {
        let minList = Double(Layout.minListWidth)
        let maxList = Double(Layout.maxListWidth)
        listWidth = min(maxList, max(minList, listWidth))

        let minDomains = Double(Layout.minDomainsWidth)
        let maxDomains = Double(Layout.urlMaxDomainsWidth)
        urlDomainsWidth = min(maxDomains, max(minDomains, urlDomainsWidth))

        let minUrlList = Double(Layout.minUrlListWidth)
        let maxUrlList = Double(Layout.urlMaxListWidth(domains: CGFloat(urlDomainsWidth)))
        urlListWidth = min(maxUrlList, max(minUrlList, urlListWidth))
    }

    private func recomputeAsync(forceFirst: Bool = false) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            applyEmptyQuery(forceFirst: forceFirst)
            return
        }
        let currentTab = tab
        let inputs: [ScoringInput] = allItems
            .filter { currentTab.matches($0) }
            .map { item in
                var fields: [String] = []
                if let s = item.text, !s.isEmpty {
                    fields.append(s)
                } else if !item.preview.isEmpty {
                    fields.append(item.preview)
                }
                if let s = item.ocrText, !s.isEmpty {
                    fields.append(s.count > 500 ? String(s.prefix(500)) : s)
                }
                if let s = item.comment, !s.isEmpty { fields.append(s) }
                return ScoringInput(id: item.id, updatedAt: item.updatedAt, fields: fields)
            }
        let scored = await Task.detached(priority: .userInitiated) { [q, inputs] in
            ContentView.performScoring(inputs: inputs, query: q)
        }.value
        if Task.isCancelled { return }
        guard q == query.trimmingCharacters(in: .whitespacesAndNewlines),
              currentTab == tab
        else { return }
        applyScored(scored, q: q, forceFirst: forceFirst)
    }

    nonisolated private static func performScoring(
        inputs: [ScoringInput],
        query: String
    ) -> [ScoredResult] {
        let fuse = Fuse(location: 0, distance: 1_000_000, threshold: 0.4)
        guard let pattern = fuse.createPattern(from: query) else { return [] }
        var scored: [(ScoringInput, Double, String, [CountableClosedRange<Int>])] = []
        scored.reserveCapacity(inputs.count)
        for input in inputs {
            if Task.isCancelled { return [] }
            var bestScore: Double?
            var bestField: String?
            var bestRanges: [CountableClosedRange<Int>] = []
            for field in input.fields {
                guard let r = fuse.search(pattern, in: field) else { continue }
                if bestScore == nil || r.score < bestScore! {
                    bestScore = r.score
                    bestField = field
                    bestRanges = r.ranges
                }
            }
            if bestScore == nil {
                for field in input.fields {
                    guard let r = SubsequenceSearch.search(pattern: query, in: field) else { continue }
                    if bestScore == nil || r.score < bestScore! {
                        bestScore = r.score
                        bestField = field
                        bestRanges = r.ranges
                    }
                }
            }
            if let s = bestScore, let field = bestField, !bestRanges.isEmpty {
                scored.append((input, s, field, bestRanges))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.0.updatedAt != rhs.0.updatedAt { return lhs.0.updatedAt > rhs.0.updatedAt }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }
        return scored.map { input, score, field, ranges in
            let snippet = SearchSnippet.build(text: field, ranges: ranges, radius: 40)
            return ScoredResult(id: input.id, score: score, snippet: snippet)
        }
    }

    private func applyEmptyQuery(forceFirst: Bool) {
        let previousById = rowsById
        let built: [RowModel] = allItems
            .filter { tab.matches($0) }
            .map { item in
                if let existing = previousById[item.id] {
                    if existing.match != nil { existing.match = nil }
                    return existing
                }
                return RowModel(item: item, match: nil)
            }
        applyBuilt(built, q: "", forceFirst: forceFirst)
    }

    private func applyScored(_ scored: [ScoredResult], q: String, forceFirst: Bool) {
        let currentById: [UUID: ClipboardItem] = Dictionary(
            uniqueKeysWithValues: allItems.map { ($0.id, $0) }
        )
        let previousById = rowsById
        var built: [RowModel] = []
        built.reserveCapacity(scored.count)
        for r in scored {
            guard let item = currentById[r.id] else { continue }
            let match = SearchMatch(score: r.score, snippet: r.snippet)
            if let existing = previousById[item.id] {
                if existing.match != match { existing.match = match }
                built.append(existing)
            } else {
                built.append(RowModel(item: item, match: match))
            }
        }
        applyBuilt(built, q: q, forceFirst: forceFirst)
    }

    private func applyBuilt(_ built: [RowModel], q: String, forceFirst: Bool) {
        let newSections = buildSections(built, query: q)
        let newById = Dictionary(uniqueKeysWithValues: built.map { ($0.id, $0) })
        var newDomainByItem: [UUID: String] = [:]
        var newDomainSections: [Section] = []
        var newSectionsByID: [String: Section] = [:]
        var newFirstRowSectionID: [UUID: String] = [:]
        newSectionsByID.reserveCapacity(newSections.count)
        for section in newSections {
            newSectionsByID[section.id] = section
            if let firstRowID = section.rows.first?.id {
                newFirstRowSectionID[firstRowID] = section.id
            }
            if section.id.hasPrefix(domainSectionPrefix) {
                let name = String(section.id.dropFirst(domainSectionPrefix.count))
                newDomainSections.append(section)
                for row in section.rows {
                    newDomainByItem[row.id] = name
                }
            }
        }
        rows = built
        sections = newSections
        rowsById = newById
        domainByItemID = newDomainByItem
        domainSectionsCache = newDomainSections
        sectionsByID = newSectionsByID
        firstRowSectionID = newFirstRowSectionID
        let visible = visibleSelectables(sections: newSections, tab: tab, query: q)
        visibleListCache = visible
        let newSelection: Selectable?
        if forceFirst {
            newSelection = visible.first
        } else if let sel = selection, visible.contains(sel) {
            newSelection = sel
        } else {
            newSelection = visible.first
        }
        applySelection(newSelection)
    }

    private func kickRecompute(forceFirst: Bool, debounce: Bool, onApplied: (@MainActor () -> Void)? = nil) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty && !debounce {
            applyEmptyQuery(forceFirst: forceFirst)
            onApplied?()
            return
        }
        searchTask = Task { @MainActor in
            if debounce {
                try? await Task.sleep(for: .milliseconds(20))
                if Task.isCancelled { return }
            }
            await recomputeAsync(forceFirst: forceFirst)
            if Task.isCancelled { return }
            onApplied?()
        }
    }

    private func applySelection(_ new: Selectable?) {
        guard selection != new else { return }
        if case let .item(oldId) = selection,
           let oldModel = rowsById[oldId],
           oldModel.isSelected {
            oldModel.isSelected = false
        }
        selection = new
        if case let .item(newId) = new,
           let newModel = rowsById[newId],
           !newModel.isSelected {
            newModel.isSelected = true
        }
    }

    private func visibleSelectables(
        sections: [Section],
        tab: Tab,
        query: String
    ) -> [Selectable] {
        let urlMode = tab == .urls && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var out: [Selectable] = []
        for section in sections {
            if urlMode, section.id.hasPrefix(domainSectionPrefix) {
                let name = String(section.id.dropFirst(domainSectionPrefix.count))
                out.append(.domain(name))
            } else {
                out.append(contentsOf: section.rows.map { .item($0.id) })
            }
        }
        return out
    }

    private func buildSections(_ list: [RowModel], query: String) -> [Section] {
        guard !list.isEmpty else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return [Section(id: "results", title: "Результаты", rows: list)]
        }
        if tab == .urls {
            return groupByDomain(list)
        }
        return groupByTime(list)
    }

    private func groupByTime(_ list: [RowModel]) -> [Section] {
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
            return Section(id: "bucket-\(i)", title: titles[i], rows: arr)
        }
    }

    private func groupByDomain(_ list: [RowModel]) -> [Section] {
        var groups: [String: [RowModel]] = [:]
        for row in list {
            let domain = Self.extractDomain(row) ?? "Без домена"
            groups[domain, default: []].append(row)
        }
        let multi = groups.filter { $0.value.count > 1 }
        let single = groups.filter { $0.value.count == 1 }
        let sortedMulti = multi.keys.sorted { lhs, rhs in
            let lc = multi[lhs]?.count ?? 0
            let rc = multi[rhs]?.count ?? 0
            if lc != rc { return lc > rc }
            let lTop = multi[lhs]?.first?.item.updatedAt ?? .distantPast
            let rTop = multi[rhs]?.first?.item.updatedAt ?? .distantPast
            return lTop > rTop
        }
        var sections: [Section] = sortedMulti.map { domain in
            let arr = multi[domain]!
            let title = "\(domain) · \(arr.count)"
            return Section(id: domainSectionPrefix + domain, title: title, rows: arr)
        }
        if !single.isEmpty {
            let combined = single.values.flatMap { $0 }.sorted {
                $0.item.updatedAt > $1.item.updatedAt
            }
            sections.append(Section(
                id: domainSectionPrefix + otherDomainKey,
                title: "Другие · \(combined.count)",
                rows: combined
            ))
        }
        return sections
    }

    private static func extractDomain(_ row: RowModel) -> String? {
        guard var host = row.parsedURL?.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host.isEmpty ? nil : host
    }

    private func resetToTop(proxy: ScrollViewProxy) {
        query = ""
        tab = .all
        searchFocused = true
        kickRecompute(forceFirst: true, debounce: false) {
            if let first = sections.first {
                proxy.scrollTo("section-\(first.id)", anchor: .top)
            }
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
                    if urlMode, backToDomains() { return .handled }
                    cycleTab(-1)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    guard query.isEmpty else { return .ignored }
                    if urlMode, enterDomainItems() { return .handled }
                    cycleTab(1)
                    return .handled
                }
                .onKeyPress(keys: [.return]) { press in
                    if case .domain = selection {
                        _ = enterDomainItems()
                        return .handled
                    }
                    if press.modifiers.contains(.shift) {
                        copyOnlySelected()
                    } else {
                        paste()
                    }
                    return .handled
                }
                .onChange(of: uiState.searchFocusToken) { _, _ in
                    searchFocused = true
                }
                .onKeyPress(.space) {
                    guard let item = selectedItem,
                          item.kind == .image,
                          let path = item.imagePath
                    else { return .ignored }
                    QuickLookController.shared.toggle(url: Storage.imageURL(for: path))
                    return .handled
                }
            if let label = togglePanelShortcutLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            pinButton
            settingsMenu
        }
        .padding(.horizontal, 18)
    }

    private var pinButton: some View {
        Button {
            settings.panelPinned.toggle()
        } label: {
            Image(systemName: settings.panelPinned ? "pin.fill" : "pin")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(settings.panelPinned ? "Открепить панель" : "Закрепить панель")
    }

    private var settingsMenu: some View {
        Button {
            uiState.showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Настройки")
    }

    private func listView(proxy: ScrollViewProxy) -> some View {
        let groups = sections
        return ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                if groups.isEmpty {
                    emptyState
                } else {
                    ForEach(groups, id: \.id) { section in
                        sectionHeader(section.title)
                            .id("section-\(section.id)")
                        ForEach(section.rows, id: \.id) { row in
                            itemRowView(row)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func itemRowView(_ row: RowModel) -> some View {
        ItemRow(model: row)
            .id(row.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { paste(row.item) }
            .simultaneousGesture(
                TapGesture().onEnded { applySelection(.item(row.id)) }
            )
    }

    private func urlThreePane(proxy: ScrollViewProxy) -> some View {
        let domainsW = CGFloat(urlDomainsWidth)
        let listW = CGFloat(urlListWidth)
        return HStack(spacing: 0) {
            domainsPane(proxy: proxy)
                .frame(width: domainsW)
            ResizableDivider(
                width: $urlDomainsWidth,
                minWidth: Double(Layout.minDomainsWidth),
                maxWidth: Double(Layout.urlMaxDomainsWidth)
            )
            .frame(width: Layout.splitDividerWidth)
            urlsPane(proxy: proxy)
                .frame(width: listW)
            ResizableDivider(
                width: $urlListWidth,
                minWidth: Double(Layout.minUrlListWidth),
                maxWidth: Double(Layout.urlMaxListWidth(domains: domainsW))
            )
            .frame(width: Layout.splitDividerWidth)
            PreviewPane(item: previewItem)
                .frame(width: Layout.urlPreviewWidth(domains: domainsW, list: listW))
        }
    }

    private func domainsPane(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if domainSections.isEmpty {
                    emptyState
                } else {
                    ForEach(domainSections, id: \.id) { section in
                        let name = String(section.id.dropFirst(domainSectionPrefix.count))
                        domainRow(name: name, count: section.rows.count)
                            .id("section-\(section.id)")
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func domainRow(name: String, count: Int) -> some View {
        DomainRow(
            name: name,
            count: count,
            isSelected: currentDomainName == name,
            onTap: { applySelection(.domain(name)) }
        )
    }

    private func urlsPane(proxy: ScrollViewProxy) -> some View {
        let rows = currentDomainRows
        return ScrollView {
            LazyVStack(spacing: 0) {
                if rows.isEmpty {
                    placeholderPane("Выбери домен")
                } else {
                    ForEach(rows, id: \.id) { row in
                        urlPathRowView(row)
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func urlPathRowView(_ row: RowModel) -> some View {
        let override: String = currentDomainName == otherDomainKey
            ? Self.stripScheme((row.item.text ?? row.item.preview).trimmingCharacters(in: .whitespacesAndNewlines))
            : Self.pathWithoutHost(row)
        return ItemRow(model: row, displayOverride: override, showBadge: false)
            .id(row.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { paste(row.item) }
            .simultaneousGesture(
                TapGesture().onEnded { applySelection(.item(row.id)) }
            )
    }

    private static func pathWithoutHost(_ row: RowModel) -> String {
        let raw = (row.item.text ?? row.item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = row.parsedURL, url.host != nil else { return Self.stripScheme(raw) }
        var tail = url.path
        if let q = url.query, !q.isEmpty { tail += "?\(q)" }
        if let f = url.fragment, !f.isEmpty { tail += "#\(f)" }
        if tail.isEmpty || tail == "/" { return Self.stripScheme(raw) }
        if tail.hasPrefix("/") { tail.removeFirst() }
        return tail
    }

    static func stripScheme(_ raw: String) -> String {
        var s = raw
        for prefix in ["https://", "http://", "ftp://"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
            break
        }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func placeholderPane(_ text: String) -> some View {
        VStack {
            Text(text)
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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
        if urlMode, case let .item(currentId) = selection {
            let list = currentDomainRows
            guard !list.isEmpty else { return }
            let idx = list.firstIndex { $0.id == currentId } ?? 0
            let new = max(0, min(list.count - 1, idx + delta))
            let next = Selectable.item(list[new].id)
            guard next != selection else { return }
            applySelection(next)
            scrollTo(next, proxy: proxy)
            return
        }
        let visible = visibleListCache
        guard !visible.isEmpty else { return }
        let idx = selection.flatMap { visible.firstIndex(of: $0) } ?? 0
        let new = max(0, min(visible.count - 1, idx + delta))
        let next = visible[new]
        guard next != selection else { return }
        applySelection(next)
        scrollTo(next, proxy: proxy)
    }

    private func scrollTo(_ target: Selectable, proxy: ScrollViewProxy) {
        switch target {
        case .item(let id):
            if let sectionID = firstRowSectionID[id] {
                proxy.scrollTo("section-\(sectionID)", anchor: .top)
            } else {
                proxy.scrollTo(id, anchor: nil)
            }
        case .domain(let name):
            proxy.scrollTo("section-domain-\(name)", anchor: .top)
        }
    }

    private func enterDomainItems() -> Bool {
        guard case let .domain(name) = selection,
              let section = sectionsByID[domainSectionPrefix + name],
              let first = section.rows.first
        else { return false }
        applySelection(.item(first.id))
        return true
    }

    private func backToDomains() -> Bool {
        guard case let .item(id) = selection,
              let name = domainByItemID[id]
        else { return false }
        applySelection(.domain(name))
        return true
    }

    private func paste(_ override: ClipboardItem? = nil) {
        if let override {
            if !Paster.shared.paste(override) { removeItem(override) }
            return
        }
        guard case let .item(id) = selection, let row = rowsById[id] else { return }
        if !Paster.shared.paste(row.item) { removeItem(row.item) }
    }

    private func copyOnlySelected() {
        guard case let .item(id) = selection, let row = rowsById[id] else { return }
        if !Paster.shared.copyOnly(row.item) { removeItem(row.item) }
    }

    private func deleteSelected() {
        guard case let .item(id) = selection, let row = rowsById[id] else { return }
        if let next = nextSelectionAfterDelete(itemID: id) {
            applySelection(next)
        }
        removeItem(row.item)
    }

    private func nextSelectionAfterDelete(itemID: UUID) -> Selectable? {
        if urlMode {
            let list = currentDomainRows
            guard let idx = list.firstIndex(where: { $0.id == itemID }) else { return nil }
            if idx + 1 < list.count { return .item(list[idx + 1].id) }
            if idx > 0 { return .item(list[idx - 1].id) }
            return nil
        }
        let visible = visibleListCache
        guard let idx = visible.firstIndex(of: .item(itemID)) else { return nil }
        if idx + 1 < visible.count { return visible[idx + 1] }
        if idx > 0 { return visible[idx - 1] }
        return nil
    }

    private func toggleFavorite() {
        guard case let .item(id) = selection, let row = rowsById[id] else { return }
        row.item.isFavorite.toggle()
        try? ctx.save()
        kickRecompute(forceFirst: false, debounce: false)
    }

    private func removeItem(_ item: ClipboardItem) {
        if let path = item.imagePath {
            let url = Storage.imageURL(for: path)
            ImageCache.invalidate(url)
            try? FileManager.default.removeItem(at: url)
        }
        if item.kind == .url {
            let raw = item.text ?? item.preview
            LinkPreviewService.delete(urlHash: URLNormalizer.hash(raw), ctx: ctx)
        }
        ctx.delete(item)
        try? ctx.save()
        kickRecompute(forceFirst: false, debounce: false)
    }
}

struct ItemRow: View {
    @Bindable var model: ContentView.RowModel
    var displayOverride: String? = nil
    var showBadge: Bool = true

    private var item: ClipboardItem { model.item }
    private var match: ContentView.SearchMatch? { model.match }
    private var selected: Bool { model.isSelected }

    private var renderedText: AttributedString {
        if let override = displayOverride {
            return AttributedString(override.replacingOccurrences(of: "\n", with: " "))
        }
        if let snippet = match?.snippet {
            return snippet
        }
        let raw = item.preview.replacingOccurrences(of: "\n", with: " ")
        if item.kind == .url {
            return AttributedString(ContentView.stripScheme(raw))
        }
        return AttributedString(raw)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if showBadge {
                leadingBadge
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
            if let path = item.imagePath,
               let image = ImageCache.thumbnail(at: Storage.imageURL(for: path), maxPixelSize: 88) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 26, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
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
        let raw = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        return LinkPreviewCard(rawURL: raw)
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
        HStack(spacing: 8) {
            if let path = item.sourceAppIconPath,
               let img = ImageCache.image(at: Storage.iconURL(for: path)) {
                Image(nsImage: img).resizable().scaledToFit().frame(width: 16, height: 16)
            }
            Text(item.sourceAppName ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("·").foregroundStyle(.tertiary).font(.caption2)
            Text(relativeFormatter.localizedString(for: item.updatedAt, relativeTo: Date()))
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

struct CommentEditor: View {
    @Bindable var item: ClipboardItem
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var uiState = UIState.shared
    @FocusState private var focused: Bool
    @State private var draft: String
    @State private var saveTask: Task<Void, Never>?

    init(item: ClipboardItem) {
        self._item = Bindable(wrappedValue: item)
        self._draft = State(initialValue: item.comment ?? "")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(minHeight: 22)
                .fixedSize(horizontal: false, vertical: true)
                .onKeyPress(.escape) {
                    focused = false
                    uiState.searchFocusToken &+= 1
                    return .handled
                }
                .onChange(of: draft) { _, newValue in
                    saveTask?.cancel()
                    let normalized: String? = newValue.isEmpty ? nil : newValue
                    let captured = ctx
                    saveTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        if item.comment != normalized {
                            item.comment = normalized
                            try? captured.save()
                        }
                    }
                }
                .onChange(of: uiState.commentFocusToken) { _, _ in
                    focused = true
                }

            if draft.isEmpty {
                Text("Комментарий…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .padding(.top, 0)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
