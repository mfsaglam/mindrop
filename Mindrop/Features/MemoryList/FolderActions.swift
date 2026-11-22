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
    let memoryID: UUID
    let move: (UUID) -> Void

    var body: some View {
        let current = folders.folderID(for: memoryID)
        Menu("Move to Folder", systemImage: "folder") {
            if current != MemoryFolders.generalID {
                Button("General") { move(MemoryFolders.generalID) }
            }
            ForEach(folders.custom) { folder in
                if current != folder.id {
                    Button(folder.name) { move(folder.id) }
                }
            }
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
