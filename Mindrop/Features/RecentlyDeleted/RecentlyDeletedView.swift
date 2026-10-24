import MindropCore
import SwiftUI

/// Deleted memories, kept for 30 days in case the delete was a mistake. Nothing here is
/// in Spotlight. Recover puts a memory back; Delete Now ends it on every device, and Delete
/// All ends every one of them.
struct RecentlyDeletedView: View {
    let repository: MemoryRepository

    /// The memory the user chose to delete for good, waiting for them to confirm.
    @State private var pendingDeletion: Memory?
    /// Delete All was tapped, waiting for the user to confirm.
    @State private var isConfirmingDeleteAll = false
    @State private var errorMessage: String?

    /// The same grid of glass cards as the list, in clear glass: set aside, not gone. Tapping
    /// a card offers Recover and Delete Now; a grid has no swipe actions.
    var body: some View {
        ScrollView {
            if !repository.deletedMemories.isEmpty {
                Text("Memories are deleted for good 30 days after you delete them, on all your devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 12)
                    .onLeadingPage()

                CardGrid {
                    ForEach(repository.deletedMemories) { memory in
                        Menu {
                            Button { recover(memory) } label: { Label("Recover", image: "ix.undo-arrow.linear") }
                            Button(role: .destructive) { pendingDeletion = memory } label: {
                                Label("Delete Now", image: "ix.trash.linear")
                            }
                        } label: {
                            DeletedMemoryCard(memory: memory)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !repository.deletedMemories.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Delete All", role: .destructive) { isConfirmingDeleteAll = true }
                        .tint(.red)
                }
            }
        }
        .alert("Delete All for Good?", isPresented: $isConfirmingDeleteAll) {
            Button("Delete All", role: .destructive) { deleteAllPermanently() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every memory in Recently Deleted will be deleted on all your devices. This can’t be undone.")
        }
        .overlay(alignment: .top) {
            if repository.deletedMemories.isEmpty {
                EmptyRecentlyDeleted()
                    .onLeadingPage()
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
            Text("Please try again.")
        }
    }

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

    private func deleteAllPermanently() {
        do {
            try repository.deletePermanently(ids: repository.deletedMemories.map(\.id))
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

/// A deleted memory: its category's icon and keyword, the value, and how long until it is
/// deleted for good, red in the last three days. Clear glass, with no category tint.
private struct DeletedMemoryCard: View {
    let memory: Memory

    @Environment(\.sensitiveAccess) private var sensitiveAccess

    private var isEndingSoon: Bool {
        guard let date = memory.deletedForGoodDate else { return false }
        return date.timeIntervalSinceNow < 3 * 24 * 60 * 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let category = memory.category?.category {
                    Image(category.symbolName)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(category.tint)
                        .accessibilityLabel(Text(category.title))
                }
                Text(memory.keyword)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if memory.isSensitive {
                    SensitiveBadge()
                }
            }
            .font(.footnote.weight(.medium))

            Group {
                if sensitiveAccess.canShow(memory) {
                    Text(memory.value)
                } else {
                    HiddenValue()
                }
            }
            .font(.headline)
            .lineLimit(2)
            .multilineTextAlignment(.leading)

            Spacer(minLength: 4)

            if let date = memory.deletedForGoodDate {
                HStack(spacing: 4) {
                    Image("ix.clock.linear")
                    // In days, so a month reads "in 30 days" rather than "next month".
                    Text(date, format: Self.daysAway)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(isEndingSoon ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Deleted for good \(date, format: Self.daysAway)"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .contentShape(.rect(cornerRadius: 22, style: .continuous))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Double tap to recover or delete now"))
    }

    private static let daysAway = Date.RelativeFormatStyle(
        allowedFields: [.day],
        presentation: .numeric,
        unitsStyle: .wide
    )
}

/// Recently Deleted with nothing in it, reached when the last memory here is recovered or
/// deleted for good. Says what the screen is for: a deleted memory's three stages.
private struct EmptyRecentlyDeleted: View {
    var body: some View {
        VStack(spacing: 28) {
            Image("ix.trash.bulk")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .frame(width: 96, height: 96)
                .glassEffect(.regular, in: .circle)
                .padding(.top, 40)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Nothing Deleted")
                    .font(.title2.weight(.bold))
                Text("A deleted memory waits here, so a mistake can be undone.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: 0) {
                stage("ix.trash.linear", Text("Deleted"))
                connector
                stage("ix.clock.linear", Text("30 days to recover"))
                connector
                stage("ix.close-circle.linear", Text("Gone for good"))
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private func stage(_ symbol: String, _ title: Text) -> some View {
        VStack(spacing: 8) {
            Image(symbol)
                .font(.title3)
                .frame(width: 52, height: 52)
                .glassEffect(.regular, in: .circle)
            title
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                // Wraps rather than truncates: "30 days to recover" needs two lines.
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 106)
    }

    private var connector: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.top, 25)
    }
}
