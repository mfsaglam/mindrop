import MindropCore
import SwiftUI

struct MemoryListView: View {
    let repository: MemoryRepository

    @State private var query = ""
    @State private var isAddingMemory = false
    @State private var deletionError: String?

    private var results: [Memory] {
        repository.results(for: query)
    }

    var body: some View {
        List {
            ForEach(results) { memory in
                NavigationLink(value: memory.id) {
                    MemoryRow(memory: memory)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Mindrop")
        .searchable(text: $query, placement: .toolbar, prompt: "Search memories")
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Memory", systemImage: "plus") { isAddingMemory = true }
            }
        }
        .overlay {
            if results.isEmpty {
                emptyState
            }
        }
        .sheet(isPresented: $isAddingMemory) {
            MemoryEditorView(mode: .create, repository: repository)
        }
        .alert("Couldn’t delete", isPresented: .constant(deletionError != nil)) {
            Button("OK") { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.isEmpty {
            ContentUnavailableView {
                Label("No Memories", systemImage: "magnifyingglass")
            } description: {
                Text("Save a value under a keyword, then search that keyword in Spotlight to see it.")
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { results[$0].id }
        do {
            try repository.delete(ids: ids)
        } catch {
            deletionError = String(describing: error)
        }
    }
}

private struct MemoryRow: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(memory.keyword)
                .font(.headline)
            Text(memory.value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
