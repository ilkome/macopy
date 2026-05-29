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
    @FocusState private var searchFocused: Bool

    @State private var rows: [RowModel] = []
    @State private var sections: [RowSection] = []
    @State private var rowsById: [UUID: RowModel] = [:]
    @State private var domainByItemID: [UUID: String] = [:]
    @State private var domainSectionsCache: [RowSection] = []
    @State private var sectionsByID: [String: RowSection] = [:]
    @State private var firstRowSectionID: [UUID: String] = [:]
    @State private var visibleListCache: [Selectable] = []
    @State private var lastAppliedStructuralHash: Int? = nil
    @State private var minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var searchTask: Task<Void, Never>?
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var uiState = UIState.shared
    @State private var keyMonitor: PanelKeyMonitor?
    @State private var pendingSelectionAfterClone: UUID?

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
            focusComment: { uiState.commentFocusToken &+= 1 },
            focusEditor: { uiState.editorFocusToken &+= 1 },
            deleteSelected: { deleteSelected() },
            cloneSelected: { cloneSelected() },
            openSelectedURL: { openSelectedURL() },
            hidePanel: { AppDelegate.shared?.hidePanel() },
            openSettings: { uiState.showSettings = true }
        ))
        monitor.install()
        keyMonitor = monitor
    }

    private func removeKeyMonitor() {
        keyMonitor?.remove()
        keyMonitor = nil
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
                kickRecompute(forceFirst: true, debounce: true) {
                    if !sections.isEmpty, let firstSection = sections.first {
                        proxy.scrollTo("section-\(firstSection.id)", anchor: .top)
                    }
                }
            }
            .onChange(of: allItemsSignature) { _, _ in
                kickRecompute(forceFirst: false, debounce: false)
            }
            .onReceive(minuteTick) { _ in
                let parsed = SearchEngine.parseQuery(query)
                sections = SectionBuilder.build(rows, query: parsed.text, tab: tab, urlFirst: parsed.urlFirst)
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
        let inputs = SearchEngine.makeInputs(items: allItems, tab: currentTab)
        let q = parsed.text
        let urlFirst = parsed.urlFirst
        let scored = await Task.detached(priority: .userInitiated) { [q, inputs, urlFirst] in
            SearchEngine.performScoring(inputs: inputs, query: q, urlFirst: urlFirst)
        }.value
        if Task.isCancelled { return }
        guard SearchEngine.parseQuery(query) == parsed,
              currentTab == tab
        else { return }
        applyScored(scored, q: q, urlFirst: urlFirst, forceFirst: forceFirst)
    }

    private func applyEmptyQuery(forceFirst: Bool) {
        let previousById = rowsById
        let built: [RowModel] = allItems
            .filter { tab.matches($0) }
            .map { item in
                if let existing = previousById[item.id] {
                    if existing.match != nil { existing.match = nil }
                    if existing.item != item { existing.item = item }
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
                    if existing.item != item { existing.item = item }
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
            let match = SearchMatch(score: r.score, snippet: r.snippet)
            if let existing = previousById[item.id] {
                if existing.match != match { existing.match = match }
                if existing.item != item { existing.item = item }
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
            rows: built.map { ($0.id, $0.item.updatedAt) }
        )
        if !forceFirst, lastAppliedStructuralHash == newHash {
            rows = built
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
        rows = built
        sections = newSections
        rowsById = newById
        domainByItemID = newDomainByItem
        domainSectionsCache = newDomainSections
        sectionsByID = newSectionsByID
        firstRowSectionID = newFirstRowSectionID
        let visible = SelectionHelpers.visibleSelectables(sections: newSections, tab: tab, query: q)
        visibleListCache = visible
        let newSelection: Selectable?
        if let pending = pendingSelectionAfterClone, visible.contains(.item(pending)) {
            pendingSelectionAfterClone = nil
            newSelection = .item(pending)
            DispatchQueue.main.async {
                uiState.editorFocusToken &+= 1
            }
        } else if forceFirst {
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
            [.favorite, .clone],
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

    /// Выполнить команду меню над конкретным элементом (по правому клику).
    private func perform(_ command: PanelCommand, on item: ClipboardItemRecord) {
        switch command {
        case .paste: paste(item)
        case .copyOnly: copyOnly(item)
        case .openURL: openURL(item)
        case .favorite: toggleFavorite(item)
        case .clone: clone(item)
        case .edit: focusEditor(item)
        case .comment: focusComment(item)
        case .quickLook: quickLook(item)
        case .delete: delete(item)
        }
    }

    private func paste(_ override: ClipboardItemRecord? = nil) {
        if let override {
            if !Paster.shared.paste(override) { removeItem(override) }
            return
        }
        guard case let .item(id) = selection, let row = rowsById[id] else { return }
        if !Paster.shared.paste(row.item) { removeItem(row.item) }
    }

    private func copyOnly(_ item: ClipboardItemRecord) {
        if !Paster.shared.copyOnly(item) { removeItem(item) }
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
        }
        if item.kind == .url {
            let raw = item.text ?? item.preview
            let hash = URLNormalizer.hash(raw)
            try? LinkPreviewRepository.deletePreview(urlHash: hash)
            store.removeCachedPreview(forHash: hash)
        }
        try? ClipboardItemRepository.deleteItem(id: item.id)
    }
}
