import Foundation

enum SectionBuilder {
    static func build(_ list: [RowModel], query: String, tab: Tab, urlFirst: Bool = false) -> [RowSection] {
        guard !list.isEmpty else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlFirst {
            return splitByURLPriority(list, searchActive: !trimmed.isEmpty)
        }
        if !trimmed.isEmpty {
            return [RowSection(id: "results", title: "Результаты", rows: list)]
        }
        if tab == .urls {
            return groupByDomain(list)
        }
        return groupByTime(list)
    }

    private static func splitByURLPriority(_ list: [RowModel], searchActive: Bool) -> [RowSection] {
        let urls = list.filter { $0.item.kind == .url }
        let others = list.filter { $0.item.kind != .url }
        var sections: [RowSection] = []
        if !urls.isEmpty {
            sections.append(RowSection(id: "results-urls", title: "Ссылки", rows: urls))
        }
        if searchActive, !others.isEmpty {
            sections.append(RowSection(id: "results-other", title: "Остальное", rows: others))
        }
        return sections
    }

    private static func groupByTime(_ list: [RowModel]) -> [RowSection] {
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
            return RowSection(id: "bucket-\(i)", title: titles[i], rows: arr)
        }
    }

    private static func groupByDomain(_ list: [RowModel]) -> [RowSection] {
        var groups: [String: [RowModel]] = [:]
        for row in list {
            let domain = URLDisplay.extractDomain(row) ?? "Без домена"
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
        var sections: [RowSection] = sortedMulti.map { domain in
            let arr = multi[domain]!
            let title = "\(domain) · \(arr.count)"
            return RowSection(id: domainSectionPrefix + domain, title: title, rows: arr)
        }
        if !single.isEmpty {
            let combined = single.values.flatMap { $0 }.sorted {
                $0.item.updatedAt > $1.item.updatedAt
            }
            sections.append(RowSection(
                id: domainSectionPrefix + otherDomainKey,
                title: "Другие · \(combined.count)",
                rows: combined
            ))
        }
        return sections
    }
}

enum URLDisplay {
    static func extractDomain(_ row: RowModel) -> String? {
        URLNormalizer.normalizedHost(row.item.text ?? row.item.preview)
    }

    static func pathWithoutHost(_ row: RowModel) -> String {
        let raw = (row.item.text ?? row.item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = row.parsedURL, url.host != nil else { return stripScheme(raw) }
        var tail = url.path
        if let q = url.query, !q.isEmpty { tail += "?\(q)" }
        if let f = url.fragment, !f.isEmpty { tail += "#\(f)" }
        if tail.isEmpty || tail == "/" { return stripScheme(raw) }
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
}
