import SwiftUI

/// Overlay card to toggle an item's folder membership and create new folders.
/// Presented inside the panel (not a popover) so it works reliably from the
/// non-activating floating panel; tap outside to dismiss.
struct FolderPicker: View {
    let itemID: UUID
    let onDismiss: () -> Void

    @ObservedObject private var store = ClipboardStore.shared
    @State private var newName: String = ""
    @FocusState private var createFocused: Bool

    private var memberFolders: Set<UUID> {
        store.itemFolderMembership[itemID] ?? []
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            card
                .frame(width: 280)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.secondary.opacity(0.2))
                )
                .shadow(radius: 20, y: 8)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Text("Add to folder")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if store.folders.isEmpty {
                Text("No folders yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.folders, id: \.id) { folder in
                            folderToggleRow(folder)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Divider()
            createRow
        }
    }

    private func folderToggleRow(_ folder: FolderRecord) -> some View {
        let isMember = memberFolders.contains(folder.id)
        return Button {
            store.toggleMembership(folderId: folder.id, itemId: itemID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isMember ? Color.accentColor : Color.secondary)
                Text(folder.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Create folder…", text: $newName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($createFocused)
                .onSubmit(createAndAdd)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { DispatchQueue.main.async { createFocused = true } }
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let folder = store.createFolder(name: name) {
            store.addToFolder(folderId: folder.id, itemId: itemID)
        }
        newName = ""
    }
}
