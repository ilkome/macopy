import Foundation

enum SelectionHelpers {
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
