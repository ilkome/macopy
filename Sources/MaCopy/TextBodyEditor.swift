import SwiftUI
import AppKit

struct TextBodyEditor: View {
    let item: ClipboardItemRecord
    @ObservedObject private var uiState = UIState.shared
    @FocusState private var focused: Bool
    @State private var draft: String
    @State private var saveTask: Task<Void, Never>?

    init(item: ClipboardItemRecord) {
        self.item = item
        self._draft = State(initialValue: item.text ?? item.preview)
    }

    var body: some View {
        TextEditor(text: $draft)
            .font(.body)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .onChange(of: draft) { _, newValue in
                saveTask?.cancel()
                guard !newValue.isEmpty else { return }
                let itemId = item.id
                saveTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    try? ClipboardItemRepository.updateText(id: itemId, newText: newValue)
                }
            }
            .onChange(of: focused) { _, isFocused in
                guard !isFocused, draft.isEmpty else { return }
                saveTask?.cancel()
                try? ClipboardItemRepository.deleteItem(id: item.id)
            }
            .onDisappear {
                guard draft.isEmpty else { return }
                saveTask?.cancel()
                try? ClipboardItemRepository.deleteItem(id: item.id)
            }
            .onChange(of: uiState.editorFocusToken) { _, _ in
                focused = true
                DispatchQueue.main.async {
                    if let tv = NSApp.keyWindow?.firstResponder as? NSTextView {
                        tv.setSelectedRange(NSRange(location: 0, length: 0))
                        tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
                    }
                }
            }
    }
}
