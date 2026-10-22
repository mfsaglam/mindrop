import MindropCore
import SwiftUI

/// Deleted memories, kept for 30 days in case the delete was a mistake. Nothing here is
/// in Spotlight. Recover puts a memory back; Delete Now ends it on every device.
struct RecentlyDeletedView: View {
    let repository: MemoryRepository

    @Environment(\.sensitiveAccess) private var sensitiveAccess
    /// The memory the user swiped to delete for good, waiting for them to confirm.
    @State private var pendingDeletion: Memory?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !repository.deletedMemories.isEmpty {
                Section {
                    ForEach(repository.deletedMemories) { memory in
                        row(for: memory)
                            .swipeActions(edge: .leading) {
                                Button { recover(memory) } label: { Label("Recover", image: "ix.undo-arrow.linear") }
                                    .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button { pendingDeletion = memory } label: { Label("Delete Now", image: "ix.trash.linear") }
                                    .tint(.red)
                            }
                            .contextMenu {
                                Button { recover(memory) } label: { Label("Recover", image: "ix.undo-arrow.linear") }
                                Button(role: .destructive) { pendingDeletion = memory } label: {
                                    Label("Delete Now", image: "ix.trash.linear")
                                }
                            }
                    }
                } footer: {
                    Text("Memories are deleted for good 30 days after you delete them, on all your devices.")
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if repository.deletedMemories.isEmpty {
                ContentUnavailableView {
                    Label("No Deleted Memories", image: "ix.trash.linear")
                } description: {
                    Text("Memories you delete stay here for 30 days.")
                }
            }
        }
        .alert(
            deletionTitle,
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { memory in
            Button("Delete", role: .destructive) { deletePermanently(memory) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This memory will be deleted on all your devices. This can’t be undone.")
        }
        .alert("Couldn’t save", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(for memory: Memory) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(memory.keyword)
                if memory.isSensitive {
                    SensitiveBadge()
                }
            }
            .font(.headline)
            Group {
                if sensitiveAccess.canShow(memory) {
                    Text(memory.value)
                } else {
                    HiddenValue()
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if let date = memory.deletedForGoodDate {
                HStack(spacing: 4) {
                    Image("ix.trash.linear")
                    // In days, so a month reads "in 30 days" rather than "next month".
                    Text("Deleted for good \(date, format: Self.daysAway)")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static let daysAway = Date.RelativeFormatStyle(
        allowedFields: [.day],
        presentation: .numeric,
        unitsStyle: .wide
    )

    private var deletionTitle: Text {
        // The keyword is user content, so it is interpolated, never looked up.
        Text("Delete “\(pendingDeletion?.keyword ?? "")” for Good?")
    }

    private func recover(_ memory: Memory) {
        do {
            try repository.recoverDeleted(memory)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func deletePermanently(_ memory: Memory) {
        do {
            try repository.deletePermanently(ids: [memory.id])
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
