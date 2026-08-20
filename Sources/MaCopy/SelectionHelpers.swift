import Foundation

enum SelectionHelpers {
    static func quickPasteAssignments(visible: [Selectable]) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: visible.prefix(9).enumerated().compactMap { index, selection in
            guard case let .item(id) = selection else { return nil }
            return (id, index + 1)
        })
    }

    static func applyQuickPasteNumbers(
        rowsById: [UUID: RowModel],
        visible: [Selectable],
        commandHeld: Bool
    ) {
        for row in rowsById.values where row.quickPasteNumber != nil {
            row.quickPasteNumber = nil
        }
        guard commandHeld else { return }
        for (id, number) in quickPasteAssignments(visible: visible) {
            rowsById[id]?.quickPasteNumber = number
        }
    }

    static func visibleSelectables(
        sections: [RowSection],
        tab: Tab,
        query: String
    ) -> [Selectable] {
        var out: [Selectable] = []
        for section in sections {
            if section.id.hasPrefix(domainSectionPrefix) {
                let name = String(section.id.dropFirst(domainSectionPrefix.count))
                out.append(.domain(name))
            } else {
                out.append(contentsOf: section.rows.map { .item($0.id) })
            }
        }
        return out
    }

    static func nextAfterDelete(
        itemID: UUID,
        urlMode: Bool,
        currentDomainRows: [RowModel],
        visibleList: [Selectable]
    ) -> Selectable? {
        if urlMode {
            let list = currentDomainRows
            guard let idx = list.firstIndex(where: { $0.id == itemID }) else { return nil }
            if idx + 1 < list.count { return .item(list[idx + 1].id) }
            if idx > 0 { return .item(list[idx - 1].id) }
            return nil
        }
        guard let idx = visibleList.firstIndex(of: .item(itemID)) else { return nil }
        if idx + 1 < visibleList.count { return visibleList[idx + 1] }
        if idx > 0 { return visibleList[idx - 1] }
        return nil
    }
}
