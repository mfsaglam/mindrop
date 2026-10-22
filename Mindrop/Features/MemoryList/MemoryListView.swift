import MindropCore
import MindropIntents
import SwiftUI
import UIKit

struct MemoryListView: View {
    private enum Sheet: Identifiable {
        case newMemory
        case settings

        var id: Self { self }
    }

    let repository: MemoryRepository
    let session: MindropSession

    @State private var query = ""
    @State private var isSearching = false
    @State private var categoryFilter: MemoryCategory?
    @State private var sheet: Sheet?
    @State private var deletionError: String?
    /// The memory the user swiped to delete, waiting for them to confirm.
    @State private var pendingDeletion: Memory?
    @AppStorage(Preference.groupsByCategory) private var groupsByCategory = true
    @Environment(\.sensitiveAccess) private var sensitiveAccess
    private let newMemoryRequest = NewMemoryRequest.shared

    /// The filter, unless its last memory has since left that category.
    private var activeCategory: MemoryCategory? {
        categoryFilter.flatMap { repository.categoriesInUse.contains($0) ? $0 : nil }
    }

    private var results: [Memory] {
        repository.results(for: query, in: activeCategory)
    }

    /// Hidden while filtering by category: an expired memory is no longer really in one.
    private var expiredResults: [Memory] {
        activeCategory == nil ? repository.expiredResults(for: query) : []
    }

    /// The way into Recently Deleted, at the very bottom, only when there is something
    /// in it and the list is not being searched or filtered.
    private var showsRecentlyDeleted: Bool {
        !repository.deletedMemories.isEmpty && query.isEmpty && activeCategory == nil
    }

    /// Sections only once something is categorised: a list of nothing but "No Category"
    /// would just be the flat list with a heading.
    private var showsSections: Bool {
        groupsByCategory && !repository.categoriesInUse.isEmpty
    }

    /// Nothing saved at all, not even expired: the list shows the Spotlight guide, which is
    /// also how a new user learns what Mindrop does. Recently Deleted may still be there.
    private var hasNoMemories: Bool {
        repository.results(for: "").isEmpty && repository.expiredResults(for: "").isEmpty
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if hasNoMemories {
                SpotlightGuide { sheet = .newMemory }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                if showsSections {
                    ForEach(results.groupedByCategory()) { section in
                        Section {
                            cards(section.memories, showsCategory: false)
                        } header: {
                            Group {
                                if let category = section.category {
                                    category.label
                                } else {
                                    Label("No Category", image: "ix.tag.linear")
                                }
                            }
                            .sectionHeaderStyle()
                        }
                    }
                } else {
                    cards(results, showsCategory: true)
                }

                if !expiredResults.isEmpty {
                    Section {
                        ForEach(expiredResults) { memory in
                            NavigationLink(value: memory.id) {
                                MemoryCard(memory: memory, showsCategory: !showsSections, query: query)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { recover(memory) } label: { Label("Recover", image: "ix.undo-arrow.linear") }
                                deleteAction(for: memory)
                            }
                        }
                    } header: {
                        Label("Expired", image: "ix.calendar-remove.linear")
                            .sectionHeaderStyle()
                    } footer: {
                        Text("Expired memories are deleted for good 7 days after they expire.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .padding(.top, showsSections ? 0 : 12)

            if showsRecentlyDeleted {
                recentlyDeleted
                    .padding(.top, 24)
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .animation(.default, value: showsSections)
        .navigationTitle("Mindrop")
        .searchable(text: $query, isPresented: $isSearching, placement: .toolbar, prompt: "Search memories")
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = .newMemory } label: { Label("New Memory", image: "ix.add.linear") }
            }
            // Search at the bottom right, where the thumb is, rather than centred.
            ToolbarSpacer(.flexible, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarItem(placement: .topBarLeading) {
                Button { sheet = .settings } label: { Label("Settings", image: "ix.setting-2.linear") }
            }
            // Only once something is categorised: without Apple Intelligence the app
            // looks exactly as it did.
            if !repository.categoriesInUse.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    categoryMenu
                }
            }
        }
        // Only for a search or a filter that finds nothing: with nothing saved, the guide
        // is in the list.
        .overlay {
            if !hasNoMemories && results.isEmpty && expiredResults.isEmpty && !showsRecentlyDeleted {
                emptyState
            }
        }
        // One sheet modifier for both: a second `.sheet` on the same view never presented.
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newMemory:
                MemoryEditorView(mode: .create, repository: repository)
            case .settings:
                SettingsView(repository: repository, categorizationLog: session.categorizationLog, session: session)
            }
        }
        // The Control Center control, the Action button or Siri asked for a new memory.
        // Replaces Settings if it was open: the user came here to write something down.
        .onChange(of: newMemoryRequest.isPending, initial: true) { _, isPending in
            guard isPending else { return }
            newMemoryRequest.isPending = false
            sheet = .newMemory
        }
        // "Search in Mindrop" in Spotlight: the same search here, across every category.
        .onChange(of: session.pendingSearch, initial: true) { _, pending in
            guard let pending else { return }
            session.pendingSearch = nil
            categoryFilter = nil
            query = pending
            isSearching = true
        }
        .alert(
            deletionTitle,
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { memory in
            Button("Delete", role: .destructive) { delete([memory.id]) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It will be removed from Spotlight and kept in Recently Deleted for 30 days.")
        }
        .alert("Couldn’t delete", isPresented: .constant(deletionError != nil)) {
            Button("OK") { deletionError = nil }
        } message: {
            Text("Please try again.")
        }
    }

    private var categoryMenu: some View {
        Menu {
            Picker("Category", selection: $categoryFilter) {
                Label("All", image: "ix.layer.linear").tag(MemoryCategory?.none)
                ForEach(repository.categoriesInUse, id: \.self) { category in
                    category.menuLabel.tag(Optional(category))
                }
            }
        } label: {
            Label("Category", image: activeCategory == nil ? "ix.filter.linear" : "ix.filter.bold")
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
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    /// In sections the header already names the category, so the card's icon is dropped.
    /// A long press offers Copy and Delete: a grid has no swipe actions.
    private func cards(_ memories: [Memory], showsCategory: Bool) -> some View {
        ForEach(memories) { memory in
            NavigationLink(value: memory.id) {
                MemoryCard(memory: memory, showsCategory: showsCategory, query: query)
            }
            .buttonStyle(.plain)
            .contextMenu {
                if sensitiveAccess.canShow(memory) {
                    Button {
                        UIPasteboard.general.string = memory.value
                    } label: {
                        Label("Copy", image: "ix.copy.linear")
                    }
                }
                deleteAction(for: memory)
            }
        }
    }

    /// The way into Recently Deleted, a glass row under the cards.
    private var recentlyDeleted: some View {
        NavigationLink {
            RecentlyDeletedView(repository: repository)
        } label: {
            HStack {
                Label("Recently Deleted", image: "ix.trash.linear")
                Spacer()
                Text(repository.deletedMemories.count, format: .number)
                    .foregroundStyle(.secondary)
                Image("ix.arrow-right-02.linear")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(.rect)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Deleting reaches every device, so the menu only asks; the alert does the deleting.
    private func deleteAction(for memory: Memory) -> some View {
        Button(role: .destructive) {
            pendingDeletion = memory
        } label: {
            Label("Delete", image: "ix.trash.linear")
        }
    }

    private var deletionTitle: Text {
        // The keyword is user content, so it is interpolated, never looked up.
        Text("Delete “\(pendingDeletion?.keyword ?? "")”?")
    }

    /// Brings an expired memory back for good, not on a new timer.
    private func recover(_ memory: Memory) {
        do {
            try repository.setExpiry(nil, for: memory)
        } catch {
            deletionError = String(describing: error)
        }
    }

    private func delete(_ ids: [UUID]) {
        do {
            try repository.delete(ids: ids)
        } catch {
            deletionError = String(describing: error)
        }
    }
}

/// A memory in the grid: the keyword small at the top, the value below as the card's
/// headline, on glass touched with the category's colour.
struct MemoryCard: View {
    let memory: Memory
    /// The category's symbol beside the keyword, when no section heading names it.
    let showsCategory: Bool
    /// The search in progress, whose words are marked in the keyword and value.
    var query: String = ""

    @Environment(\.sensitiveAccess) private var sensitiveAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if showsCategory, let category = memory.category?.category {
                    Image(category.symbolName)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(category.tint)
                        .accessibilityLabel(Text(category.title))
                }
                HighlightedText(memory.keyword, query: query)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if memory.isSensitive {
                    SensitiveBadge()
                }
            }
            .font(.footnote.weight(.medium))

            Spacer(minLength: 0)

            Group {
                if sensitiveAccess.canShow(memory) {
                    HighlightedText(memory.value, query: query)
                } else {
                    HiddenValue()
                }
            }
            .font(.headline)
            .lineLimit(3)
            .multilineTextAlignment(.leading)

            if let expiry = ExpiryText(memory: memory) {
                expiry
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .contentShape(.rect(cornerRadius: 22, style: .continuous))
        .glassEffect(.category(memory.category?.category).interactive(), in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// A section's heading over the cards: the category's tinted symbol and its name.
    func sectionHeaderStyle() -> some View {
        font(.headline)
            .padding(.top, 16)
            .padding(.leading, 4)
    }
}

/// "Expires tomorrow" for a temporary memory, "Deleted for good in 6 days" for an expired
/// one, nothing for a memory kept forever. Shared by the list and the detail screen.
struct ExpiryText: View {
    private let memory: Memory
    private let isExpired: Bool

    init?(memory: Memory, now: Date = .now) {
        guard memory.expiresAt != nil else { return nil }
        self.memory = memory
        isExpired = memory.isExpired(at: now)
    }

    var body: some View {
        HStack(spacing: 4) {
            if isExpired, let deletion = memory.deletionDate {
                Image("ix.trash.linear")
                Text("Deleted for good \(deletion, format: .relative(presentation: .named))")
            } else if let expiry = memory.expiresAt {
                Image("ix.timer.linear")
                Text("Expires \(expiry, format: .relative(presentation: .named))")
            }
        }
    }
}
