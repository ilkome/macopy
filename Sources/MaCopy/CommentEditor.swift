import SwiftUI

struct CommentEditor: View {
    let item: ClipboardItemRecord
    @ObservedObject private var uiState = UIState.shared
    @FocusState private var focused: Bool
    @State private var draft: String
    @State private var saveTask: Task<Void, Never>?

    init(item: ClipboardItemRecord) {
        self.item = item
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
                .onChange(of: draft) { _, newValue in
                    saveTask?.cancel()
                    let normalized: String? = newValue.isEmpty ? nil : newValue
                    let itemId = item.id
                    saveTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        try? ClipboardItemRepository.updateComment(id: itemId, comment: normalized)
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
