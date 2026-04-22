import AppKit
import SwiftData
import SwiftUI

struct DomainRow: View {
    let name: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    @Query private var previews: [LinkPreview]

    init(name: String, count: Int, isSelected: Bool, onTap: @escaping () -> Void) {
        self.name = name
        self.count = count
        self.isSelected = isSelected
        self.onTap = onTap
        let host = name
        var fetch = FetchDescriptor<LinkPreview>(
            predicate: #Predicate { $0.hostname == host }
        )
        fetch.fetchLimit = 8
        _previews = Query(fetch)
    }

    private var isOther: Bool { name == "__other__" }
    private var iconData: Data? {
        previews.first { $0.iconData != nil }?.iconData
    }
    private var displayName: String { isOther ? "Другие" : name }

    var body: some View {
        HStack(spacing: 8) {
            iconView
            Text(displayName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? .primary : .secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Layout.rowHeight)
        .background(Color.accentColor.opacity(isSelected ? 0.3 : 0))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    @ViewBuilder
    private var iconView: some View {
        if isOther {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 18, height: 18)
        } else if let data = iconData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 18, height: 18)
        }
    }
}
