import MindropCore
import SwiftUI

struct NewFolderView: View {
    let folders: MemoryFolders

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var name = ""
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            MemorySheetForm {
                TextField("Folder Name", text: $name)
                    .focused($nameFocused)
                    .onSubmit(save)
            }
            .navigationTitle("New Folder")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: save)
                        .disabled(MemoryNormalizer.normalizeValue(name).isEmpty)
                }
            }
            .alert("Couldn’t save", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again.")
            }
            .defaultFocus($nameFocused, true)
            .onAppear {
                #if os(macOS)
                // The sheet can appear before AppKit makes its window key.
                DispatchQueue.main.async { nameFocused = true }
                #else
                nameFocused = true
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 350, minHeight: 180)
        #endif
    }

    private func save() {
        guard !MemoryNormalizer.normalizeValue(name).isEmpty else { return }
        do {
            try folders.add(named: name)
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

struct MoveToFolderMenu: View {
    let folders: MemoryFolders
    let sourceFolderID: UUID
    let move: (UUID) -> Void

    var body: some View {
        Menu("Move to Folder", systemImage: "folder") {
            if sourceFolderID != MemoryFolders.generalID {
                Button("General") { move(MemoryFolders.generalID) }
            }
            ForEach(folders.custom) { folder in
                if sourceFolderID != folder.id {
                    Button(folder.name) { move(folder.id) }
                }
            }
        }
    }
}

struct FolderSelectionMenu: View {
    let repository: MemoryRepository
    let folderID: UUID
    let selection: [Memory]
    let requestDeletion: ([Memory]) -> Void
    let onSuccess: () -> Void
    let onFailure: () -> Void
    var showsSelectionCount = false

    var body: some View {
        let stackAdditions = selection.filter {
            repository.isEligibleForStack($0) && !repository.isInStack($0.id)
        }.map(\.id)

        Menu {
            MoveToFolderMenu(folders: repository.folders, sourceFolderID: folderID) { destination in
                perform { try repository.move(ids: selection.map(\.id), to: destination) }
            }
            .disabled(repository.folders.custom.isEmpty)

            Button {
                perform { try repository.setStackMembership(stackAdditions, included: true) }
            } label: {
                Label {
                    if !stackAdditions.isEmpty, stackAdditions.count < selection.count {
                        Text("Add to Stack (\(stackAdditions.count))")
                    } else {
                        Text("Add to Stack")
                    }
                } icon: {
                    Image(systemName: "square.stack")
                }
            }
            .disabled(stackAdditions.isEmpty)

            Button("Delete", systemImage: "trash", role: .destructive) { requestDeletion(selection) }
        } label: {
            if showsSelectionCount {
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityHidden(true)
                    Text("\(selection.count) selected")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .accessibilityLabel("Manage Memories")
                        .accessibilityValue(Text("\(selection.count) selected"))
                }
                .padding(.horizontal, 8)
            } else {
                Label("Manage Memories", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
        }
        .disabled(selection.isEmpty)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            onSuccess()
        } catch {
            onFailure()
        }
    }
}

extension MemoryFolders {
    func title(for id: UUID) -> Text {
        if let folder = custom.first(where: { $0.id == id }) {
            Text(folder.name)
        } else {
            Text("General")
        }
    }
}

extension View {
    func memoryDeletionAlert(
        for memories: Binding<[Memory]>, onDelete: @escaping ([UUID]) -> Void
    ) -> some View {
        let pending = memories.wrappedValue
        let title = if pending.count > 1 {
            Text("Delete \(pending.count) memories?")
        } else {
            Text("Delete “\(pending.first?.keyword ?? "")”?")
        }
        return alert(
            title,
            isPresented: Binding(
                get: { !memories.wrappedValue.isEmpty },
                set: { if !$0 { memories.wrappedValue = [] } }
            ),
            presenting: pending
        ) { selection in
            Button("Delete", role: .destructive) { onDelete(selection.map(\.id)) }
            Button("Cancel", role: .cancel) {}
        } message: { selection in
            if selection.count > 1 {
                Text("These memories will be removed from Spotlight and kept in Recently Deleted for 30 days.")
            } else {
                Text("It will be removed from Spotlight and kept in Recently Deleted for 30 days.")
            }
        }
    }

    func folderDeletionAlert(
        for folder: Binding<MemoryFolder?>, onDelete: @escaping (MemoryFolder) -> Void
    ) -> some View {
        alert(
            Text("Delete folder “\(folder.wrappedValue?.name ?? "")”?"),
            isPresented: Binding(
                get: { folder.wrappedValue != nil },
                set: { if !$0 { folder.wrappedValue = nil } }
            ),
            presenting: folder.wrappedValue
        ) { folder in
            Button("Cancel", role: .cancel) {}
            Button("Delete Folder", role: .destructive) { onDelete(folder) }
        } message: { _ in
            Text("The folder will be removed. Its memories will move to Recently Deleted, where you can recover them for 30 days.")
        }
    }
}
