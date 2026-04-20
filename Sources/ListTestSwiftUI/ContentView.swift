import SwiftUI

struct ContentView: View {
    @State private var selection: Int = 0
    @FocusState private var focused: Bool

    private let itemCount = 50
    private let itemsPerSection = 10
    private let rowHeight: CGFloat = 40
    private let sectionTitles = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"]

    private var sections: [(title: String, items: [Int])] {
        stride(from: 0, to: itemCount, by: itemsPerSection).enumerated().map { idx, start in
            let end = min(start + itemsPerSection, itemCount)
            let title = idx < sectionTitles.count ? sectionTitles[idx] : "Section \(idx + 1)"
            return (title, Array(start..<end))
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        sectionHeader(section.title)
                        ForEach(section.items, id: \.self) { item in
                            row(item)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                let step = press.modifiers.contains(.shift) ? 2 : 1
                let direction = press.key == .upArrow ? -1 : 1
                move(by: step * direction, proxy: proxy)
                return .handled
            }
        }
        .frame(width: 400, height: 140)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
    }

    private func row(_ item: Int) -> some View {
        HStack {
            Text("Item \(item)")
                .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .background(
            item == selection
                ? Color.accentColor.opacity(0.35)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture { selection = item }
        .id(item)
    }

    private func move(by delta: Int, proxy: ScrollViewProxy) {
        let new = max(0, min(itemCount - 1, selection + delta))
        guard new != selection else { return }
        selection = new
        proxy.scrollTo(new, anchor: nil)
    }
}
