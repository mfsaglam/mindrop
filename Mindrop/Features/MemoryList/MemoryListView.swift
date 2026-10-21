import MindropCore
import MindropIntents
import SwiftUI

struct MemoryListView: View {
    private enum Sheet: Identifiable {
        case newMemory
        case settings

        var id: Self { self }
    }

    let repository: MemoryRepository
    let categorizationLog: CategorizationLog?

    @State private var query = ""
    @State private var categoryFilter: MemoryCategory?
    @State private var sheet: Sheet?
    @State private var deletionError: String?
    /// The memory the user swiped to delete, waiting for them to confirm.
    @State private var pendingDeletion: Memory?
    @AppStorage(Preference.groupsByCategory) private var groupsByCategory = true
    private let newMemoryRequest = NewMemoryRequest.shared

    /// The filter, unless its last memory has since left that category.
    private var activeCategory: MemoryCategory? {
        categoryFilter.flatMap { repository.categoriesInUse.contains($0) ? $0 : nil }
    }

    private var results: [Memory] {
        repository.results(for: query, in: activeCategory)
    }

    /// Sections only once something is categorised: a list of nothing but "No Category"
    /// would just be the flat list with a heading.
    private var showsSections: Bool {
        groupsByCategory && !repository.categoriesInUse.isEmpty
    }

    var body: some View {
        List {
            if showsSections {
                ForEach(results.groupedByCategory()) { section in
                    Section {
                        rows(section.memories, showsCategory: false)
                    } header: {
                        if let category = section.category {
                            category.label
                        } else {
                            Label("No Category", systemImage: "tag")
                        }
                    }
                }
            } else {
                rows(results, showsCategory: true)
            }
        }
        .animation(.default, value: showsSections)
        .navigationTitle("Mindrop")
        .searchable(text: $query, placement: .toolbar, prompt: "Search memories")
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Memory", systemImage: "plus") { sheet = .newMemory }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { sheet = .settings }
            }
            // Only once something is categorised: without Apple Intelligence the app
            // looks exactly as it did.
            if !repository.categoriesInUse.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    categoryMenu
                }
            }
        }
        .overlay {
            if results.isEmpty {
                emptyState
            }
        }
        // One sheet modifier for both: a second `.sheet` on the same view never presented.
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newMemory:
                MemoryEditorView(mode: .create, repository: repository)
            case .settings:
                SettingsView(repository: repository, categorizationLog: categorizationLog)
            }
        }
        // The Control Center control, the Action button or Siri asked for a new memory.
        // Replaces Settings if it was open: the user came here to write something down.
        .onChange(of: newMemoryRequest.isPending, initial: true) { _, isPending in
            guard isPending else { return }
            newMemoryRequest.isPending = false
            sheet = .newMemory
        }
        .alert(
            deletionTitle,
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { memory in
            Button("Delete", role: .destructive) { delete([memory.id]) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This memory will be permanently deleted and removed from Spotlight. This can’t be undone.")
        }
        .alert("Couldn’t delete", isPresented: .constant(deletionError != nil)) {
            Button("OK") { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
    }

    private var categoryMenu: some View {
        Menu {
            Picker("Category", selection: $categoryFilter) {
                Label("All", systemImage: "tray.full").tag(MemoryCategory?.none)
                ForEach(repository.categoriesInUse, id: \.self) { category in
                    category.label.tag(Optional(category))
                }
            }
        } label: {
            Label(
                "Category",
                systemImage: activeCategory == nil
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let activeCategory, query.isEmpty {
            ContentUnavailableView {
                activeCategory.label
            } description: {
                Text("Nothing in this category.")
            }
        } else if query.isEmpty {
            ContentUnavailableView {
                Label("No Memories", systemImage: "magnifyingglass")
            } description: {
                Text("Save a value under a keyword, then search that keyword in Spotlight to see it.")
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    /// In sections the header already names the category, so the row's icon is dropped.
    private func rows(_ memories: [Memory], showsCategory: Bool) -> some View {
        ForEach(memories) { memory in
            NavigationLink(value: memory.id) {
                MemoryRow(memory: memory, showsCategory: showsCategory)
            }
            .swipeActions(edge: .trailing) {
                deleteAction(for: memory)
            }
        }
    }

    /// Deleting is permanent, so a swipe only asks; the alert does the deleting. Not
    /// `onDelete`, which removes the row at once, and not a `.destructive` role, which
    /// animates the row away before the user has answered.
    private func deleteAction(for memory: Memory) -> some View {
        Button {
            pendingDeletion = memory
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(.red)
    }

    private var deletionTitle: Text {
        // The keyword is user content, so it is interpolated, never looked up.
        Text("Delete “\(pendingDeletion?.keyword ?? "")”?")
    }

    private func delete(_ ids: [UUID]) {
        do {
            try repository.delete(ids: ids)
        } catch {
            deletionError = String(describing: error)
        }
    }
}

private struct MemoryRow: View {
    let memory: Memory
    let showsCategory: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Always present in the flat list, so rows line up whether or not they are
            // categorised yet.
            if showsCategory {
                Group {
                    if let category = memory.category?.category {
                        Image(systemName: category.symbolName)
                            .accessibilityLabel(Text(category.title))
                    } else {
                        Color.clear
                    }
                }
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(memory.keyword)
                    .font(.headline)
                Text(memory.value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
