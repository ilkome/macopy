import AppKit
import KeyboardShortcuts
import SwiftUI

struct ContentView: View {
    @StateObject private var store = ClipboardStore.shared
    private var allItems: [ClipboardItemRecord] { store.items }

    @State private var query: String = ""
    @State private var selection: Selectable?
    @State private var tab: Tab = .all
    @AppStorage("listWidth") private var listWidth: Double = Double(Layout.defaultListWidth)
    @AppStorage("urlDomainsWidth") private var urlDomainsWidth: Double = Double(Layout.defaultDomainsWidth)
    @AppStorage("urlListWidth") private var urlListWidth: Double = Double(Layout.defaultUrlListWidth)
    @AppStorage("folderListWidth") private var folderListWidth: Double = Double(Layout.defaultFolderListWidth)
    @AppStorage("folderItemsWidth") private var folderItemsWidth: Double = Double(Layout.defaultFolderItemsWidth)
    @FocusState private var searchFocused: Bool

    @State private var rows: [RowModel] = []
    @State private var sections: [RowSection] = []
    @State private var rowsById: [UUID: RowModel] = [:]
    @State private var domainByItemID: [UUID: String] = [:]
    @State private var domainSectionsCache: [RowSection] = []
    @State private var sectionsByID: [String: RowSection] = [:]
    @State private var firstRowSectionID: [UUID: String] = [:]
    @State private var visibleListCache: [Selectable] = []
    @State private var cmdHeld = false
    @State private var lastAppliedStructuralHash: Int? = nil
    @State private var minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var searchTask: Task<Void, Never>?
    // Held so a superseded scoring run can be cancelled - Task.detached is not a child
    // of searchTask, so cancelling searchTask alone leaves stale scans running.
    @State private var scoringTask: Task<[SearchEngine.ScoredResult], Never>?
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var uiState = UIState.shared
    @State private var keyMonitor: PanelKeyMonitor?
    @State private var pendingSelectionAfterClone: UUID?
    // Direct handle on the highlighted row so its flag is cleared even after the row
    // leaves rowsById (e.g. a tab switch) - otherwise a stale isSelected ghosts on reopen.
    @State private var selectedRowModel: RowModel?
    // Folders tab: the active folder whose items fill the middle pane. Explicit state
    // (not derived from the selected item) because membership is many-to-many.
    @State private var selectedFolderID: UUID?
    @State private var renamingFolderID: UUID?
    @State private var folderPickerTarget: UUID?
    @State private var showFolderPicker = false

    private var selectedItem: ClipboardItemRecord? {
        guard case let .item(id) = selection else { return nil }
        return rowsById[id]?.item
    }

    private var previewItem: ClipboardItemRecord? {
        switch selection {
        case .item(let id):
            return rowsById[id]?.item
        case .domain(let name):
            return sectionsByID[domainSectionPrefix + name]?.rows.first?.item
        case .folder:
            return currentFolderRows.first?.item
        case .none:
            return nil
        }
    }

    private var urlMode: Bool {
        tab == .urls && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var folderMode: Bool {
        tab == .folders && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Loaded rows belonging to the active folder, most recently used first. Members that aged out
    /// of the 2000-item window simply aren't in rowsById (mirrors favorites behavior).
    private var currentFolderRows: [RowModel] {
        guard let fid = selectedFolderID, let ids = store.folderMembership[fid] else { return [] }
        let useDates = store.folderItemLastUsedAt[fid] ?? [:]
        return ids.compactMap { rowsById[$0] }.sorted { lhs, rhs in
            let lhsDate = useDates[lhs.id] ?? .distantPast
            let rhsDate = useDates[rhs.id] ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            if lhs.item.updatedAt != rhs.item.updatedAt { return lhs.item.updatedAt > rhs.item.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func folderMemberCount(_ id: UUID) -> Int {
        (store.folderMembership[id] ?? []).reduce(into: 0) { acc, itemId in
            if rowsById[itemId] != nil { acc += 1 }
        }
    }

    private var togglePanelShortcutLabel: String? {
        KeyboardShortcuts.getShortcut(for: .togglePanel).map { "\($0)" }
    }

    private var currentDomainName: String? {
        switch selection {
        case .domain(let name): return name
        case .item(let id): return domainByItemID[id]
        case .folder: return nil
        case .none: return nil
        }
    }

    private var currentDomainRows: [RowModel] {
        guard let name = currentDomainName else { return [] }
        return sectionsByID[domainSectionPrefix + name]?.rows ?? []
    }

    private var domainSections: [RowSection] {
        domainSectionsCache
    }

    private struct AllItemsSignature: Equatable {
        let count: Int
        let topUpdatedAt: Date?
        let dataVersion: Int
    }

    private var allItemsSignature: AllItemsSignature {
        AllItemsSignature(
            count: allItems.count,
            topUpdatedAt: allItems.first?.updatedAt,
            dataVersion: store.dataVersion
        )
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
        let monitor = PanelKeyMonitor(callbacks: .init(
            isItemSelected: {
                if case .item = selection { return true }
                return false
            },
            isURLSelected: { selectedItem?.kind == .url },
            toggleFavorite: { toggleFavorite() },
            openFolderPicker: { if case let .item(id) = selection { openFolderPicker(for: id) } },
            focusComment: { uiState.commentFocusToken &+= 1 },
            focusEditor: { uiState.editorFocusToken &+= 1 },
            deleteSelected: { deleteSelected() },
            cloneSelected: { cloneSelected() },
            openSelectedURL: { openSelectedURL() },
            hidePanel: {
                setCommandHeld(false)
                AppDelegate.shared?.hidePanel()
            },
            openSettings: { uiState.showSettings = true },
            pasteAt: { n in
                guard n >= 1, n <= visibleListCache.count,
                      case let .item(id) = visibleListCache[n - 1],
                      let row = rowsById[id] else { return false }
                paste(row.item)
                return true
            },
            setCommandHeld: { setCommandHeld($0) }
        ))
        monitor.install()
        keyMonitor = monitor
    }

    private func removeKeyMonitor() {
        setCommandHeld(false)
        keyMonitor?.remove()
        keyMonitor = nil
    }

    private func setCommandHeld(_ held: Bool) {
        guard cmdHeld != held else { return }
        cmdHeld = held
        refreshQuickPasteNumbers()
    }

    private func refreshQuickPasteNumbers() {
        SelectionHelpers.applyQuickPasteNumbers(
            rowsById: rowsById,
            visible: visibleListCache,
            commandHeld: cmdHeld
        )
    }

    @ViewBuilder
    private func contentArea(proxy: ScrollViewProxy) -> some View {
        if folderMode {
            folderThreePane(proxy: proxy)
        } else if urlMode {
            urlThreePane(proxy: proxy)
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
        }
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
                contentArea(proxy: proxy)
                    .frame(height: Layout.listHeight)
            }
            .overlay { folderPickerOverlay }
            .onReceive(NotificationCenter.default.publisher(for: .clipboardPanelReset)) { _ in
                resetToTop(proxy: proxy)
            }
            .onChange(of: tab) { _, newTab in
                kickRecompute(forceFirst: true, debounce: false) {
                    scrollToFirstSection(proxy: proxy)
                }
                if newTab == .folders {
                    // SectionBuilder yields no sections for folders, so the recompute
                    // clears selection; point it at the active (or first) folder.
                    if let target = selectedFolderID ?? store.folders.first?.id {
                        applySelection(.folder(target))
                    }
                }
            }
            .onChange(of: query) { _, newValue in
                // Debounce real typing only; clearing to empty applies synchronously
                // so full history shows at once (same invariant as a tab switch) and
                // leaves no pending task that could later yank the selection to top.
                let isEmpty = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                kickRecompute(forceFirst: true, debounce: !isEmpty) {
                    scrollToFirstSection(proxy: proxy)
                }
            }
            .onChange(of: allItemsSignature) { _, _ in
                // Skip while hidden: reopening rebuilds from fresh store.items via
                // resetToTop, so background writes don't drive O(n) recomputes off-screen.
                guard uiState.isPanelVisible else { return }
                kickRecompute(forceFirst: false, debounce: false)
            }
            .onReceive(minuteTick) { _ in
                // Time buckets only shift while visible; reopening rebuilds from fresh
                // store.items anyway. And republish only when bucket membership actually
                // moved, else every minute re-renders the whole list for nothing.
                guard uiState.isPanelVisible else { return }
                let parsed = SearchEngine.parseQuery(query)
                let rebuilt = SectionBuilder.build(rows, query: parsed.text, tab: tab, urlFirst: parsed.urlFirst)
                let membershipChanged = rebuilt.count != sections.count
                    || zip(rebuilt, sections).contains { $0.id != $1.id || $0.rows.count != $1.rows.count }
                if membershipChanged { sections = rebuilt }
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

        let minFolderList = Double(Layout.minFolderListWidth)
        let maxFolderList = Double(Layout.folderMaxListWidth)
        folderListWidth = min(maxFolderList, max(minFolderList, folderListWidth))

        let minFolderItems = Double(Layout.minFolderItemsWidth)
        let maxFolderItems = Double(Layout.folderMaxItemsWidth(list: CGFloat(folderListWidth)))
        folderItemsWidth = min(maxFolderItems, max(minFolderItems, folderItemsWidth))
    }

    private func recomputeAsync(forceFirst: Bool = false) async {
        let parsed = SearchEngine.parseQuery(query)
        if parsed.text.isEmpty && !parsed.urlFirst {
            applyEmptyQuery(forceFirst: forceFirst)
            return
        }
        if parsed.text.isEmpty && parsed.urlFirst {
            applyURLsOnly(forceFirst: forceFirst)
            return
        }
        let currentTab = tab
        let previews = store.previewsByHash
        let items = allItems
        let q = parsed.text
        let urlFirst = parsed.urlFirst
        // makeInputs (filter + per-URL SHA256 + string allocs) runs off-main too, so a
        // keystroke never touches the corpus on the main thread.
        scoringTask?.cancel()
        let task = Task.detached(priority: .userInitiated) { [items, currentTab, previews, q, urlFirst] in
            let inputs = SearchEngine.makeInputs(items: items, tab: currentTab, previewsByHash: previews)
            return SearchEngine.performScoring(inputs: inputs, query: q, urlFirst: urlFirst)
        }
        scoringTask = task
        let scored = await task.value
        if Task.isCancelled { return }
        guard SearchEngine.parseQuery(query) == parsed,
              currentTab == tab
        else { return }
        applyScored(scored, q: q, urlFirst: urlFirst, forceFirst: forceFirst)
    }

    /// Cheap reconcile check: avoids a full Equatable memcmp of `text`/`ocrText`.
    /// Covers every mutation path - updateText bumps updatedAt+contentHash, while
    /// favorite/comment/ocr edits don't touch updatedAt, so each is compared directly.
    nonisolated static func rowItemUnchanged(
        _ a: ClipboardItemRecord,
        _ b: ClipboardItemRecord
    ) -> Bool {
        a.id == b.id
            && a.updatedAt == b.updatedAt
            && a.contentHash == b.contentHash
            && a.isFavorite == b.isFavorite
            && a.comment == b.comment
            && a.imagePath == b.imagePath
            && a.ocrText == b.ocrText
            && a.copyCount == b.copyCount
            && a.pasteCount == b.pasteCount
            && a.lastFavoriteUsedAt == b.lastFavoriteUsedAt
            && a.lastSiteUsedAt == b.lastSiteUsedAt
    }

    private func applyEmptyQuery(forceFirst: Bool) {
        let previousById = rowsById
        let built: [RowModel] = allItems
            .filter { tab.matches($0) }
            .sorted { lhs, rhs in
                let lhsDate: Date = switch tab {
                case .favorites: lhs.lastFavoriteUsedAt
                case .urls: lhs.lastSiteUsedAt
                default: lhs.updatedAt
                }
                let rhsDate: Date = switch tab {
                case .favorites: rhs.lastFavoriteUsedAt
                case .urls: rhs.lastSiteUsedAt
                default: rhs.updatedAt
                }
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.updatedAt > rhs.updatedAt
            }
            .map { item in
                if let existing = previousById[item.id] {
                    if existing.match != nil { existing.match = nil }
                    if !Self.rowItemUnchanged(existing.item, item) { existing.item = item }
                    return existing
                }
                return RowModel(item: item, match: nil)
            }
        applyBuilt(built, q: "", urlFirst: false, forceFirst: forceFirst)
    }

    private func applyURLsOnly(forceFirst: Bool) {
        let previousById = rowsById
        let built: [RowModel] = allItems
            .filter { $0.kind == .url }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { item in
                if let existing = previousById[item.id] {
                    if existing.match != nil { existing.match = nil }
                    if !Self.rowItemUnchanged(existing.item, item) { existing.item = item }
                    return existing
                }
                return RowModel(item: item, match: nil)
            }
        applyBuilt(built, q: "", urlFirst: true, forceFirst: forceFirst)
    }

    private func applyScored(_ scored: [SearchEngine.ScoredResult], q: String, urlFirst: Bool, forceFirst: Bool) {
        let currentById: [UUID: ClipboardItemRecord] = Dictionary(
            uniqueKeysWithValues: allItems.map { ($0.id, $0) }
        )
        let previousById = rowsById
        var built: [RowModel] = []
        built.reserveCapacity(scored.count)
        for r in scored {
            guard let item = currentById[r.id] else { continue }
            let match = SearchMatch(score: r.score, field: r.field, ranges: r.ranges)
            if let existing = previousById[item.id] {
                if existing.match != match { existing.match = match }
                if !Self.rowItemUnchanged(existing.item, item) { existing.item = item }
                built.append(existing)
            } else {
                built.append(RowModel(item: item, match: match))
            }
        }
        applyBuilt(built, q: q, urlFirst: urlFirst, forceFirst: forceFirst)
    }

    nonisolated static func structuralBuildHash(
        q: String,
        urlFirst: Bool,
        tab: Tab,
        rows: [(UUID, Date)]
    ) -> Int {
        SearchEngine.structuralBuildHash(q: q, urlFirst: urlFirst, tab: tab, rows: rows)
    }

    private func applyBuilt(_ built: [RowModel], q: String, urlFirst: Bool, forceFirst: Bool) {
        let newHash = SearchEngine.structuralBuildHash(
            q: q,
            urlFirst: urlFirst,
            tab: tab,
            rows: built.map { row in
                let date: Date = switch tab {
                case .favorites: row.item.lastFavoriteUsedAt
                case .urls: row.item.lastSiteUsedAt
                default: row.item.updatedAt
                }
                return (row.id, date)
            }
        )
        if lastAppliedStructuralHash == newHash {
            rows = built
            // Structure is identical (reopen with no new clips, or a redundant reset
            // trigger): skip the O(n) section/index rebuild. forceFirst still snaps the
            // selection to top - that's the only thing a reopen needs to change here.
            if forceFirst {
                applySelection(visibleListCache.first)
            }
            return
        }
        lastAppliedStructuralHash = newHash
        let newSections = SectionBuilder.build(built, query: q, tab: tab, urlFirst: urlFirst)
        let newById = Dictionary(uniqueKeysWithValues: built.map { ($0.id, $0) })
        var newDomainByItem: [UUID: String] = [:]
        var newDomainSections: [RowSection] = []
        var newSectionsByID: [String: RowSection] = [:]
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
        SelectionHelpers.applyQuickPasteNumbers(
            rowsById: rowsById,
            visible: [],
            commandHeld: false
        )
        rows = built
        sections = newSections
        rowsById = newById
        domainByItemID = newDomainByItem
        domainSectionsCache = newDomainSections
        sectionsByID = newSectionsByID
        firstRowSectionID = newFirstRowSectionID
        let visible = SelectionHelpers.visibleSelectables(sections: newSections, tab: tab, query: q)
        visibleListCache = visible
        refreshQuickPasteNumbers()
        let newSelection: Selectable?
        let currentSelectionStillVisible: Bool = {
            guard let selection else { return false }
            if visible.contains(selection) { return true }
            guard case let .item(id) = selection, newById[id] != nil else { return false }
            if urlMode { return newDomainByItem[id] != nil }
            if folderMode, let folderID = selectedFolderID {
                return store.folderMembership[folderID]?.contains(id) == true
            }
            return false
        }()
        if let pending = pendingSelectionAfterClone, visible.contains(.item(pending)) {
            pendingSelectionAfterClone = nil
            newSelection = .item(pending)
            DispatchQueue.main.async {
                uiState.editorFocusToken &+= 1
            }
        } else if forceFirst {
            newSelection = visible.first
        } else if let sel = selection, currentSelectionStillVisible {
            newSelection = sel
        } else {
            newSelection = visible.first
        }
        applySelection(newSelection)
    }

    private func kickRecompute(forceFirst: Bool, debounce: Bool, onApplied: (@MainActor () -> Void)? = nil) {
        searchTask?.cancel()
        scoringTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty && !debounce {
            applyEmptyQuery(forceFirst: forceFirst)
            onApplied?()
            return
        }
        searchTask = Task { @MainActor in
            if debounce {
                try? await Task.sleep(for: .milliseconds(90))
                if Task.isCancelled { return }
            }
            await recomputeAsync(forceFirst: forceFirst)
            if Task.isCancelled { return }
            onApplied?()
        }
    }

    private func applySelection(_ new: Selectable?) {
        // Selecting a folder updates the active folder; selecting an item leaves it intact.
        if case let .folder(id) = new { selectedFolderID = id }
        let newModel: RowModel? = {
            if case let .item(id) = new { return rowsById[id] }
            return nil
        }()
        if selectedRowModel !== newModel {
            let outgoing = selectedRowModel
            newModel?.isSelected = true
            selectedRowModel = newModel
            if let outgoing, outgoing !== newModel {
                if rowsById[outgoing.item.id] === outgoing {
                    // Still present in this view - safe to unhighlight immediately.
                    outgoing.isSelected = false
                } else {
                    // Outgoing row is leaving this tab. Clearing its observable flag now
                    // re-renders its outgoing ItemRow straight into the incoming tab as a
                    // ghost first row. Defer until the swap settles (its row is gone by
                    // then), and skip if it got reselected in the meantime.
                    DispatchQueue.main.async {
                        if self.selectedRowModel !== outgoing { outgoing.isSelected = false }
                    }
                }
            }
        } else if let m = newModel, !m.isSelected {
            m.isSelected = true
        }
        if selection != new { selection = new }
    }

    private func resetToTop(proxy: ScrollViewProxy) {
        setCommandHeld(false)
        query = ""
        tab = .all
        searchFocused = true
        showFolderPicker = false
        folderPickerTarget = nil
        renamingFolderID = nil
        kickRecompute(forceFirst: true, debounce: false) {
            scrollToFirstSection(proxy: proxy)
        }
    }

    /// Scroll the list back to the top. Deferred a runloop so the freshly built
    /// sections are laid out first - scrolling synchronously targets a section id the
    /// new tab hasn't realized yet, so the list stays where the previous tab left it
    /// and the selected first row ends up above the viewport.
    private func scrollToFirstSection(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            guard let first = sections.first else { return }
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
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
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
                    if folderMode, backToFolder() { return .handled }
                    cycleTab(-1)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    guard query.isEmpty else { return .ignored }
                    if urlMode, enterDomainItems() { return .handled }
                    if folderMode, enterFolderItems() { return .handled }
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
                    guard let item = selectedItem, item.kind == .image else { return .ignored }
                    quickLook(item)
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
        .help(settings.panelPinned ? "Unpin panel" : "Pin panel")
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
        .help("Settings")
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
                TapGesture().onEnded {
                    applySelection(.item(row.id))
                    uiState.searchFocusToken &+= 1
                }
            )
            .contextMenu { rowContextMenu(row.item) }
    }

    /// Контекстное меню по правому клику: команды над конкретным элементом с
    /// инлайн-подсказкой комбинации клавиш. Группы разделены `Divider`.
    @ViewBuilder
    private func rowContextMenu(_ item: ClipboardItemRecord) -> some View {
        let groups: [[PanelCommand]] = [
            [.paste, .copyOnly, .openURL],
            [.favorite, .addToFolder, .clone],
            [.edit, .comment, .quickLook],
            [.delete]
        ]
        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            let available = group.filter { $0.isAvailable(for: item) }
            if !available.isEmpty {
                if index > 0 { Divider() }
                ForEach(available) { command in
                    contextMenuButton(command, item: item)
                }
            }
        }
    }

    /// Кнопка пункта меню. Для ⌘-команд используем `.keyboardShortcut` —
    /// глиф прижимается к правому краю. Для ⏎/⇧⏎/␣ показываем глиф инлайн.
    @ViewBuilder
    private func contextMenuButton(_ command: PanelCommand, item: ClipboardItemRecord) -> some View {
        let role: ButtonRole? = command == .delete ? .destructive : nil
        if let shortcut = command.nativeShortcut {
            Button(role: role) {
                perform(command, on: item)
            } label: {
                Label(command.title(for: item), systemImage: command.symbol)
            }
            .keyboardShortcut(shortcut)
        } else {
            Button(role: role) {
                perform(command, on: item)
            } label: {
                Label(
                    "\(command.title(for: item))  \(command.shortcutDisplay)",
                    systemImage: command.symbol
                )
            }
        }
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
            onTap: {
                applySelection(.domain(name))
                uiState.searchFocusToken &+= 1
            }
        )
    }

    private func urlsPane(proxy: ScrollViewProxy) -> some View {
        let rows = currentDomainRows
        return ScrollView {
            LazyVStack(spacing: 0) {
                if rows.isEmpty {
                    placeholderPane("Select a domain")
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
            ? URLDisplay.stripScheme((row.item.text ?? row.item.preview).trimmingCharacters(in: .whitespacesAndNewlines))
            : URLDisplay.pathWithoutHost(row)
        return ItemRow(model: row, displayOverride: override, showBadge: false)
            .id(row.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { paste(row.item) }
            .simultaneousGesture(
                TapGesture().onEnded {
                    applySelection(.item(row.id))
                    uiState.searchFocusToken &+= 1
                }
            )
            .contextMenu { rowContextMenu(row.item) }
    }

    private func placeholderPane(_ text: LocalizedStringKey) -> some View {
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
            Text(query.isEmpty ? "History is empty" : "Nothing found")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func move(_ delta: Int, proxy: ScrollViewProxy) {
        if folderMode {
            if case let .item(currentId) = selection {
                let list = currentFolderRows
                guard !list.isEmpty else { return }
                let idx = list.firstIndex { $0.id == currentId } ?? 0
                let new = max(0, min(list.count - 1, idx + delta))
                let next = Selectable.item(list[new].id)
                guard next != selection else { return }
                applySelection(next)
                scrollTo(next, proxy: proxy)
                return
            }
            let folders = store.folders
            guard !folders.isEmpty else { return }
            let curIdx: Int
            if case let .folder(fid) = selection {
                curIdx = folders.firstIndex { $0.id == fid } ?? 0
            } else {
                curIdx = 0
            }
            let new = max(0, min(folders.count - 1, curIdx + delta))
            let next = Selectable.folder(folders[new].id)
            guard next != selection else { return }
            applySelection(next)
            scrollTo(next, proxy: proxy)
            return
        }
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
        case .folder(let id):
            proxy.scrollTo("section-\(folderSectionPrefix)\(id.uuidString)", anchor: .top)
        }
    }

    private func enterFolderItems() -> Bool {
        guard case .folder = selection, let first = currentFolderRows.first else { return false }
        applySelection(.item(first.id))
        return true
    }

    private func backToFolder() -> Bool {
        guard case .item = selection, let fid = selectedFolderID else { return false }
        applySelection(.folder(fid))
        return true
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

    /// Выполнить команду меню над конкретным элементом (по правому клику).
    private func perform(_ command: PanelCommand, on item: ClipboardItemRecord) {
        switch command {
        case .paste: paste(item)
        case .copyOnly: copyOnly(item)
        case .openURL: openURL(item)
        case .favorite: toggleFavorite(item)
        case .addToFolder: openFolderPicker(for: item.id)
        case .clone: clone(item)
        case .edit: focusEditor(item)
        case .comment: focusComment(item)
        case .quickLook: quickLook(item)
        case .delete: delete(item)
        }
    }

    private func paste(_ override: ClipboardItemRecord? = nil) {
        if let override {
            if Paster.shared.paste(override) {
                recordSectionUse(itemID: override.id)
            } else {
                removeItem(override)
            }
            return
        }
        guard case let .item(id) = selection, let row = rowsById[id] else { return }
        if Paster.shared.paste(row.item) {
            recordSectionUse(itemID: row.id)
        } else {
            removeItem(row.item)
        }
    }

    private func copyOnly(_ item: ClipboardItemRecord) {
        if Paster.shared.copyOnly(item) {
            recordSectionUse(itemID: item.id)
        } else {
            removeItem(item)
        }
    }

    private func recordSectionUse(itemID: UUID) {
        if folderMode, let folderID = selectedFolderID {
            store.recordFolderUse(folderId: folderID, itemId: itemID)
        } else if urlMode {
            try? ClipboardItemRepository.recordSiteUse(id: itemID)
        } else if tab == .favorites,
                  query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? ClipboardItemRepository.recordFavoriteUse(id: itemID)
        }
    }

    private func copyOnlySelected() {
        guard let item = selectedItem else { return }
        copyOnly(item)
    }

    private func delete(_ item: ClipboardItemRecord) {
        if selection == .item(item.id) {
            let next = SelectionHelpers.nextAfterDelete(
                itemID: item.id,
                urlMode: urlMode,
                currentDomainRows: currentDomainRows,
                visibleList: visibleListCache
            )
            if let next {
                applySelection(next)
            }
        }
        removeItem(item)
    }

    private func deleteSelected() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    private func toggleFavorite(_ item: ClipboardItemRecord) {
        try? ClipboardItemRepository.updateFavorite(id: item.id, isFavorite: !item.isFavorite)
    }

    private func toggleFavorite() {
        guard let item = selectedItem else { return }
        toggleFavorite(item)
    }

    private func clone(_ item: ClipboardItemRecord) {
        guard item.kind == .text else { return }
        if let newId = try? ClipboardItemRepository.cloneItem(id: item.id) {
            pendingSelectionAfterClone = newId
        }
    }

    private func cloneSelected() {
        guard let item = selectedItem else { return }
        clone(item)
    }

    private func openURL(_ item: ClipboardItemRecord) {
        guard item.kind == .url else { return }
        let raw = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
        AppDelegate.shared?.hidePanel()
    }

    private func openSelectedURL() {
        guard let item = selectedItem else { return }
        openURL(item)
    }

    /// Выбрать ряд и сфокусировать редактор текста в превью.
    private func focusEditor(_ item: ClipboardItemRecord) {
        applySelection(.item(item.id))
        uiState.editorFocusToken &+= 1
    }

    /// Выбрать ряд и сфокусировать поле комментария в превью.
    private func focusComment(_ item: ClipboardItemRecord) {
        applySelection(.item(item.id))
        uiState.commentFocusToken &+= 1
    }

    private func quickLook(_ item: ClipboardItemRecord) {
        guard item.kind == .image,
              let path = item.imagePath,
              let url = try? ImageStore.tempPlaintextURL(for: path)
        else { return }
        QuickLookController.shared.toggle(url: url)
    }

    private func removeItem(_ item: ClipboardItemRecord) {
        if let path = item.imagePath {
            ImageCache.invalidateClipboardImage(filename: path)
            ImageStore.delete(filename: path)
            ImageStore.delete(filename: ImageCache.thumbFilename(for: path))
        }
        if item.kind == .url {
            let raw = item.text ?? item.preview
            let hash = URLNormalizer.hash(raw)
            try? LinkPreviewRepository.deletePreview(urlHash: hash)
            store.removeCachedPreview(forHash: hash)
        }
        try? FolderRepository.deleteMembershipsForItem(itemId: item.id)
        try? ClipboardItemRepository.deleteItem(id: item.id)
    }

    private func openFolderPicker(for itemID: UUID) {
        folderPickerTarget = itemID
        showFolderPicker = true
        searchFocused = false
    }

    private func deleteFolder(_ id: UUID) {
        let remaining = store.folders.filter { $0.id != id }
        store.deleteFolder(id: id)
        if renamingFolderID == id { renamingFolderID = nil }
        if selectedFolderID == id {
            applySelection(remaining.first.map { .folder($0.id) })
            if remaining.isEmpty { selectedFolderID = nil }
        }
    }

    @ViewBuilder
    private var folderPickerOverlay: some View {
        if showFolderPicker, let target = folderPickerTarget {
            FolderPicker(itemID: target) {
                showFolderPicker = false
                folderPickerTarget = nil
                DispatchQueue.main.async { searchFocused = true }
            }
        }
    }

    private func folderThreePane(proxy: ScrollViewProxy) -> some View {
        let listW = CGFloat(folderListWidth)
        let itemsW = CGFloat(folderItemsWidth)
        return HStack(spacing: 0) {
            foldersPane(proxy: proxy)
                .frame(width: listW)
            ResizableDivider(
                width: $folderListWidth,
                minWidth: Double(Layout.minFolderListWidth),
                maxWidth: Double(Layout.folderMaxListWidth)
            )
            .frame(width: Layout.splitDividerWidth)
            folderItemsPane(proxy: proxy)
                .frame(width: itemsW)
            ResizableDivider(
                width: $folderItemsWidth,
                minWidth: Double(Layout.minFolderItemsWidth),
                maxWidth: Double(Layout.folderMaxItemsWidth(list: listW))
            )
            .frame(width: Layout.splitDividerWidth)
            PreviewPane(item: previewItem)
                .frame(width: Layout.folderPreviewWidth(list: listW, items: itemsW))
        }
    }

    private func foldersPane(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.folders, id: \.id) { folder in
                    folderRowView(folder)
                        .id("section-\(folderSectionPrefix)\(folder.id.uuidString)")
                }
                createFolderInlineRow
            }
        }
        .scrollIndicators(.never)
    }

    private func folderRowView(_ folder: FolderRecord) -> some View {
        FolderRow(
            folder: folder,
            count: folderMemberCount(folder.id),
            isSelected: selectedFolderID == folder.id,
            isRenaming: renamingFolderID == folder.id,
            onTap: {
                applySelection(.folder(folder.id))
                uiState.searchFocusToken &+= 1
            },
            onCommitRename: { newName in
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != folder.name {
                    store.renameFolder(id: folder.id, name: trimmed)
                }
                renamingFolderID = nil
            }
        )
        .contextMenu {
            Button { renamingFolderID = folder.id } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) { deleteFolder(folder.id) } label: {
                Label("Delete folder", systemImage: "trash")
            }
        }
    }

    private var createFolderInlineRow: some View {
        Button {
            if let folder = store.createFolder(name: String(localized: "New folder")) {
                applySelection(.folder(folder.id))
                renamingFolderID = folder.id
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                Text("New folder")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Layout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func folderItemsPane(proxy: ScrollViewProxy) -> some View {
        let rows = currentFolderRows
        return ScrollView {
            LazyVStack(spacing: 0) {
                if selectedFolderID == nil {
                    placeholderPane("Select a folder")
                } else if rows.isEmpty {
                    placeholderPane("Folder is empty")
                } else {
                    ForEach(rows, id: \.id) { row in
                        itemRowView(row)
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }
}
