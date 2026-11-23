import MindropCore
import SwiftUI

struct MemoryStackView: View {
    let repository: MemoryRepository
    #if os(macOS)
    let selection: Binding<UUID?>
    #else
    let pullFeedback: FolderPullFeedback
    let isActiveScreen: Bool
    #endif

    @State private var showsPicker = false
    @State private var changeFailed = false

    var body: some View {
        let memories = repository.stackMemories
        stackList(memories)
            .overlay {
                if memories.isEmpty {
                    ContentUnavailableView {
                        Label("Stack is Empty", systemImage: "square.stack")
                    } description: {
                        Text("Choose memories from your folders to keep them together here.")
                    } actions: {
                        Button("Choose Memories") { showsPicker = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(.brandCobalt))
                    }
                    .onLeadingPage()
                }
            }
            .navigationTitle("Stack")
            .toolbar {
                if !memories.isEmpty {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Choose Memories", systemImage: "plus") { showsPicker = true }
                        #if os(iOS)
                        if memories.count > 1 { EditButton() }
                        #endif
                    }
                }
            }
            .sheet(isPresented: $showsPicker) {
                StackMemoryPicker(repository: repository)
            }
            .alert("Couldn’t save", isPresented: $changeFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again.")
            }
    }

    @ViewBuilder
    private func stackList(_ memories: [Memory]) -> some View {
        #if os(macOS)
        List(selection: selection) { rows(memories) }
        #else
        List { rows(memories) }
            .listStyle(.plain)
            .modifier(FolderPullScrollFeedback(
                feedback: pullFeedback,
                enabled: isActiveScreen && !showsPicker && !changeFailed,
                onLaunch: { showsPicker = true }
            ))
            .navigationLinkIndicatorVisibility(.hidden)
            .onLeadingPage()
            .memoryScreenBackground(usesGradient: true)
        #endif
    }

    private func rows(_ memories: [Memory]) -> some View {
        ForEach(Array(memories.enumerated()), id: \.element.id) { index, memory in
            row(for: memory)
                .contextMenu {
                    if index > 0 {
                        Button("Move Up", systemImage: "arrow.up") { move(memory.id, by: -1) }
                    }
                    if index + 1 < memories.count {
                        Button("Move Down", systemImage: "arrow.down") { move(memory.id, by: 1) }
                    }
                    Button("Remove from Stack", systemImage: "minus.circle") {
                        remove(memory.id)
                    }
                }
        }
        .onMove { offsets, destination in
            var order = memories.map(\.id)
            order.move(fromOffsets: offsets, toOffset: destination)
            change { try repository.reorderStack(order) }
        }
    }

    @ViewBuilder
    private func row(for memory: Memory) -> some View {
        #if os(macOS)
        StackMemoryLabel(memory: memory)
            .padding(.vertical, 4)
            .tag(memory.id)
        #else
        NavigationLink(value: LibraryRoute.memory(memory.id)) {
            HStack(spacing: 12) {
                StackMemoryLabel(memory: memory)
                Image("ix.arrow-right-02.linear")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(.rect)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Remove from Stack", systemImage: "minus.circle") {
                remove(memory.id)
            }
            .tint(.red)
        }
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        #endif
    }

    private func remove(_ id: UUID) {
        change { try repository.setStackMembership([id], included: false) }
    }

    private func move(_ id: UUID, by offset: Int) {
        var order = repository.stackMemories.map(\.id)
        guard let position = order.firstIndex(of: id), order.indices.contains(position + offset) else { return }
        order.swapAt(position, position + offset)
        change { try repository.reorderStack(order) }
    }

    private func change(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            changeFailed = true
        }
    }
}

struct StackMemoryPicker: View {
    let repository: MemoryRepository

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: [UUID] = []
    @State private var saveFailed = false

    var body: some View {
        let candidates = repository.stackCandidates(matching: query)
        let byFolder = Dictionary(grouping: candidates) { repository.folders.folderID(for: $0.id) }
        NavigationStack {
            MemorySheetForm {
                section(for: MemoryFolders.generalID, memories: byFolder[MemoryFolders.generalID] ?? [])
                ForEach(repository.folders.custom) { folder in
                    section(for: folder.id, memories: byFolder[folder.id] ?? [])
                }
            }
            .overlay {
                if candidates.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView("No Memories to Add", systemImage: "square.stack")
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .navigationTitle("Choose Memories")
            .inlineNavigationTitle()
            .searchable(text: $query, prompt: "Search memories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .disabled(selected.isEmpty)
                }
            }
            .alert("Couldn’t save", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 360)
        #endif
    }

    @ViewBuilder
    private func section(for folderID: UUID, memories: [Memory]) -> some View {
        if !memories.isEmpty {
            Section {
                ForEach(memories) { memory in
                    let isSelected = selected.contains(memory.id)
                    Button {
                        if let index = selected.firstIndex(of: memory.id) {
                            selected.remove(at: index)
                        } else {
                            selected.append(memory.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            StackMemoryLabel(memory: memory)
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color(.folderAccent) : .secondary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            } header: {
                repository.folders.title(for: folderID)
            }
        }
    }

    private func save() {
        do {
            try repository.setStackMembership(selected, included: true)
            dismiss()
        } catch {
            let available = Set(repository.stackCandidates(matching: "").map(\.id))
            selected.removeAll { !available.contains($0) }
            saveFailed = true
        }
    }
}

private struct StackMemoryLabel: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(memory.keyword)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(memory.value)
                .font(.headline)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
