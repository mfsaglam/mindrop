#if os(iOS)
import MindropCore
import MindropIntents
import MindropWidgetData
import SwiftUI

struct MemoryListView: View {
    private enum Sheet: Hashable, Identifiable {
        case newMemory(folderID: UUID, scanning: Bool = false)
        case newFolder
        case stackPicker
        case settings

        var id: Self { self }
    }

    let repository: MemoryRepository
    let session: MindropSession
    var folderID: UUID? = nil
    let folderPullFeedback: FolderPullFeedback

    @State private var query = ""
    @State private var isSearching = false
    @State private var categoryFilter: MemoryCategory?
    @State private var sheet: Sheet?
    @State private var changeFailed = false
    @State private var selectedIDs: Set<UUID>?
    @State private var pendingDeletion: [Memory] = []
    @State private var pendingFolderDeletion: MemoryFolder?
    @AppStorage(Preference.groupsByCategory) private var groupsByCategory = true
    @ScaledMetric(relativeTo: .title3) private var folderIconWidth: CGFloat = 24
    @Environment(\.sensitiveAccess) private var sensitiveAccess
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let newMemoryRequest = NewMemoryRequest.shared

    private var isShowingFolders: Bool { folderID == nil && query.allSatisfy(\.isWhitespace) }

    private var canPullForFeedback: Bool {
        guard !isSearching, query.allSatisfy(\.isWhitespace), !isSelecting, sheet == nil else { return false }
        if let folderID { return session.path.last == .folder(folderID) }
        return session.path.isEmpty
    }

    private var categories: [MemoryCategory] { repository.categories(in: folderID) }

    /// The filter, unless its last memory has since left that category.
    private var activeCategory: MemoryCategory? {
        categoryFilter.flatMap { categories.contains($0) ? $0 : nil }
    }

    private var results: [Memory] {
        repository.results(for: query, in: activeCategory, folderID: folderID)
    }

    /// Hidden while filtering by category: an expired memory is no longer really in one.
    private var expiredResults: [Memory] {
        activeCategory == nil ? repository.expiredResults(for: query, folderID: folderID) : []
    }

    private var isSelecting: Bool { selectedIDs != nil }

    private var selectedMemories: [Memory] {
        guard let folderID, let selectedIDs, !selectedIDs.isEmpty else { return [] }
        return repository.memories.filter {
            selectedIDs.contains($0.id) && !$0.isDeleted && repository.folders.folderID(for: $0.id) == folderID
        }
    }

    /// Sections only once something is categorised: a list of nothing but "No Category"
    /// would just be the flat list with a heading.
    private var showsSections: Bool {
        groupsByCategory && !categories.isEmpty
    }

    /// Nothing saved at all, not even expired: the list shows the Spotlight guide, which is
    /// also how a new user learns what Mindrop does.
    private var hasNoMemories: Bool {
        repository.results(for: "", folderID: folderID).isEmpty
            && repository.expiredResults(for: "", folderID: folderID).isEmpty
    }

    var body: some View {
        ScrollView {
            if isShowingFolders {
                folderList
            } else {
                memoryGrid
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .modifier(FolderPullScrollFeedback(
            feedback: folderPullFeedback,
            enabled: canPullForFeedback,
            onLaunch: {
                if folderID == nil { createFolder() } else { createMemory() }
            }
        ))
        .animation(.default, value: showsSections)
        .navigationTitle(folderID.map { repository.folders.title(for: $0) } ?? Text("Mindrop"))
        .searchable(text: $query, isPresented: $isSearching, placement: .toolbar, prompt: "Search memories")
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let folderID, isSelecting {
                    FolderSelectionMenu(
                        repository: repository, folderID: folderID, selection: selectedMemories,
                        requestDeletion: { pendingDeletion = $0 },
                        onSuccess: { selectedIDs = nil },
                        onFailure: { changeFailed = true },
                        showsSelectionCount: true
                    )
                } else {
                    if folderID == nil {
                        Button("New Folder", systemImage: "folder.badge.plus", action: createFolder)
                        .labelStyle(.iconOnly)
                        .tint(Color(.folderAccent))
                    }
                    Button(action: createMemory) { Label("New Memory", image: "ix.add.linear") }
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            if folderID != nil {
                ToolbarItemGroup(placement: .bottomBar) {
                    if !categories.isEmpty {
                        categoryMenu
                    }
                    if isSelecting {
                        Button("Done") { selectedIDs = nil }
                    } else {
                        Button("Choose Memories", systemImage: "checkmark.circle") { selectedIDs = [] }
                            .labelStyle(.iconOnly)
                            .disabled(results.isEmpty && expiredResults.isEmpty)
                    }
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
            } else {
                ToolbarItemGroup(placement: .memoryLeading) {
                    Button { sheet = .settings } label: { Label("Settings", image: "ix.setting-2.linear") }
                    if !isShowingFolders, !categories.isEmpty {
                        categoryMenu
                    }
                }
            }
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
        .overlay {
            if !isShowingFolders, results.isEmpty, expiredResults.isEmpty {
                emptyState.onLeadingPage().allowsHitTesting(false)
            }
        }
        // One sheet modifier for both: a second `.sheet` on the same view never presented.
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newMemory(let folderID, let scanning):
                MemoryEditorView(
                    mode: .create, repository: repository, startsScanning: scanning, folderID: folderID
                )
            case .newFolder:
                NewFolderView(folders: repository.folders)
            case .stackPicker:
                StackMemoryPicker(repository: repository)
            case .settings:
                SettingsView(repository: repository, session: session)
            }
        }
        // A Control Center control, the Action button or Siri asked for a new memory.
        // Replaces Settings if it was open: the user came here to write something down.
        .onChange(of: newMemoryRequest.isPending, initial: true) { _, isPending in
            let openFolderID = session.path.compactMap { route -> UUID? in
                if case .folder(let id) = route { return id }
                return nil
            }.last
            guard isPending, folderID == openFolderID else { return }
            newMemoryRequest.isPending = false
            sheet = .newMemory(folderID: MemoryFolders.generalID, scanning: newMemoryRequest.scans)
        }
        // "Search in Mindrop" in Spotlight: the same search here, across every category.
        .onChange(of: session.pendingSearch, initial: true) { _, pending in
            guard folderID == nil, let pending else { return }
            session.pendingSearch = nil
            categoryFilter = nil
            query = pending
            isSearching = true
        }
        .memoryDeletionAlert(for: $pendingDeletion, onDelete: delete)
        .folderDeletionAlert(for: $pendingFolderDeletion) { folder in
            change { try repository.deleteFolder(folder.id) }
        }
        .alert("Couldn’t save", isPresented: $changeFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    private var folderList: some View {
        let counts = repository.results(for: "").reduce(into: [UUID: Int]()) { counts, memory in
            counts[repository.folders.folderID(for: memory.id), default: 0] += 1
        }
        let deletedCount = repository.deletedMemories.count
        return LazyVStack(spacing: 10) {
            stackPreview(repository.stackMemories)
                .padding(.bottom, 6)
            folderRow(
                Text("General"), count: counts[MemoryFolders.generalID, default: 0],
                route: .folder(MemoryFolders.generalID)
            )
            ForEach(repository.folders.custom) { folder in
                folderRow(Text(folder.name), count: counts[folder.id, default: 0], route: .folder(folder.id))
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingFolderDeletion = folder
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    }
            }
            if deletedCount > 0 {
                folderRow(
                    Text("Recently Deleted"), icon: Image("ix.trash.linear"),
                    count: deletedCount, route: .recentlyDeleted
                )
            }
        }
        .padding(.top, 8)
        .onLeadingPage()
    }

    @ViewBuilder
    private func stackPreview(_ memories: [Memory]) -> some View {
        if memories.isEmpty {
            Button {
                sheet = .stackPicker
            } label: {
                HStack(spacing: 10) {
                    stackTitle
                    Spacer(minLength: 0)
                    Label("Choose Memories", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(.folderAccent))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 52)
                .contentShape(.rect)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: LibraryRoute.stack) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        stackTitle
                        Spacer(minLength: 0)
                        Image("ix.arrow-right-02.linear")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 2)

                    StackWidgetGrid(records: memories.prefix(StackWidgetGrid.capacity).map(
                        StackWidgetSnapshot.Record.init(memory:)
                    ))
                        .background(StackWidgetGrid.background, in: .rect(cornerRadius: 23))
                        .overlay {
                            RoundedRectangle(cornerRadius: 23)
                                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var stackTitle: some View {
        Label {
            Text("Stack")
        } icon: {
            Image(systemName: "square.stack")
                .foregroundStyle(Color(.folderAccent))
        }
        .font(.subheadline.weight(.semibold))
    }

    private func folderRow(
        _ title: Text, icon: Image = Image(systemName: "folder"), count: Int, route: LibraryRoute
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                icon
                    .font(.title3)
                    .foregroundStyle(Color(.folderAccent))
                    .frame(width: folderIconWidth)
                    .accessibilityHidden(true)
                title
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Spacer(minLength: 0)
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .accessibilityLabel(Text("Memory Count"))
                    .accessibilityValue(Text(count, format: .number))
                Image("ix.arrow-right-02.linear")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .frame(minHeight: 60)
            .contentShape(.rect)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var memoryGrid: some View {
        if folderID == MemoryFolders.generalID, hasNoMemories, query.isEmpty,
           repository.results(for: "").isEmpty, repository.expiredResults(for: "").isEmpty {
            SpotlightGuide(newMemory: createMemory)
        }

        CardGrid {
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
                        if isSelecting {
                            selectionCard(memory, showsCategory: !showsSections)
                        } else {
                            NavigationLink(value: LibraryRoute.memory(memory.id)) {
                                MemoryCard(memory: memory, showsCategory: !showsSections, query: query)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { recover(memory) } label: { Label("Recover", image: "ix.undo-arrow.linear") }
                                moveMenu(for: memory)
                                deleteAction(for: memory)
                            }
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
                        .onLeadingPage()
                }
            }
        }
        .padding(.top, showsSections ? 0 : 12)
    }

    private func createFolder() {
        sheet = .newFolder
    }

    private func createMemory() {
        sheet = .newMemory(folderID: folderID ?? MemoryFolders.generalID)
    }

    private var categoryMenu: some View {
        Menu {
            Picker("Category", selection: $categoryFilter) {
                Label("All", image: "ix.layer.linear").tag(MemoryCategory?.none)
                ForEach(categories, id: \.self) { category in
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
        } else if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if folderID != MemoryFolders.generalID
                    || !repository.results(for: "").isEmpty || !repository.expiredResults(for: "").isEmpty {
            ContentUnavailableView("No Memories", systemImage: "folder")
        }
    }

    /// In sections the header already names the category, so the card's icon is dropped.
    /// A long press opens the card's actions.
    private func cards(_ memories: [Memory], showsCategory: Bool) -> some View {
        ForEach(memories) { memory in
            if isSelecting {
                selectionCard(memory, showsCategory: showsCategory)
            } else {
                NavigationLink(value: LibraryRoute.memory(memory.id)) {
                    MemoryCard(memory: memory, showsCategory: showsCategory, query: query)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if sensitiveAccess.canShow(memory) {
                        Button {
                            Clipboard.copy(memory.value)
                        } label: {
                            Label("Copy", image: "ix.copy.linear")
                        }
                    }
                    if repository.isEligibleForStack(memory), !repository.isInStack(memory.id) {
                        Button("Add to Stack", systemImage: "square.stack") {
                            change { try repository.setStackMembership([memory.id], included: true) }
                        }
                    }
                    moveMenu(for: memory)
                    deleteAction(for: memory)
                }
            }
        }
    }

    private func selectionCard(_ memory: Memory, showsCategory: Bool) -> some View {
        let isSelected = selectedIDs?.contains(memory.id) == true
        return Button {
            if isSelected {
                selectedIDs?.remove(memory.id)
            } else {
                selectedIDs?.insert(memory.id)
            }
        } label: {
            MemoryCard(memory: memory, showsCategory: showsCategory, query: query, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func moveMenu(for memory: Memory) -> some View {
        if !repository.folders.custom.isEmpty {
            let source = repository.folders.folderID(for: memory.id)
            MoveToFolderMenu(folders: repository.folders, sourceFolderID: source) { id in
                change { try repository.move(memory, to: id) }
            }
        }
    }

    /// Deleting reaches every device, so the menu only asks; the alert does the deleting.
    private func deleteAction(for memory: Memory) -> some View {
        Button(role: .destructive) {
            pendingDeletion = [memory]
        } label: {
            Label("Delete", image: "ix.trash.linear")
        }
    }

    /// Brings an expired memory back for good, not on a new timer.
    private func recover(_ memory: Memory) {
        change { try repository.setExpiry(nil, for: memory) }
    }

    private func delete(_ ids: [UUID]) {
        change {
            try repository.delete(ids: ids)
            selectedIDs = nil
        }
    }

    private func change(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            changeFailed = true
        }
    }

}

/// A memory in the grid: the keyword small at the top, the value below as the card's
/// headline, on regular glass.
struct MemoryCard: View {
    let memory: Memory
    /// The category's symbol beside the keyword, when no section heading names it.
    let showsCategory: Bool
    /// The search in progress, whose words are marked in the keyword and value.
    var query: String = ""
    /// A checkmark is shown when the card is in selection mode.
    var isSelected: Bool?

    @Environment(\.sensitiveAccess) private var sensitiveAccess
    @ScaledMetric(relativeTo: .body) private var selectionMarkSpace: CGFloat = 26

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
            .padding(.trailing, isSelected == nil ? 0 : selectionMarkSpace)

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
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if let isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? Color(.folderAccent) : .secondary)
                    .padding(14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
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
#endif
