import SwiftUI

/// Left-pane row in the Folders tab. Mirrors DomainRow, plus inline rename.
struct FolderRow: View {
    let folder: FolderRecord
    let count: Int
    let isSelected: Bool
    let isRenaming: Bool
    let onTap: () -> Void
    let onCommitRename: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .secondary : .tertiary)
                .frame(width: 18, height: 18)
            if isRenaming {
                TextField("Folder name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($renameFocused)
                    .onSubmit { onCommitRename(draft) }
                    .onChange(of: renameFocused) { _, focused in
                        // Commit when focus leaves the field (clicked elsewhere).
                        if !focused { onCommitRename(draft) }
                    }
            } else {
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Layout.rowHeight)
        .background(Color.accentColor.opacity(isSelected ? 0.3 : 0))
        .contentShape(Rectangle())
        .onTapGesture { if !isRenaming { onTap() } }
        .onChange(of: isRenaming) { _, now in
            if now { startEditing() }
        }
        .onAppear { if isRenaming { startEditing() } }
    }

    private func startEditing() {
        draft = folder.name
        DispatchQueue.main.async { renameFocused = true }
    }
}
