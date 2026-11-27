#if os(macOS)
import MindropCore
import SwiftUI

struct MacLibraryView: View {
    private enum Area: Hashable {
        case folder(UUID)
        case stack
        case expired
        case recentlyDeleted
    }

    let repository: MemoryRepository
    let session: MindropSession

    @State private var area: Area? = .folder(MemoryFolders.generalID)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var query = ""
    @State private var isSearching = false
    @State private var selectedIDs: Set<UUID>?
    @State private var pendingDeletion: [Memory] = []
    @State private var pendingFolderDeletion: MemoryFolder?
    @State private var isConfirmingEmptyTrash = false
    @State private var changeFailed = false
    @State private var folderEditor: FolderEditorView.Mode?
    @AppStorage(Preference.groupsByCategory) private var groupsByCategory = true
    @Environment(\.sensitiveAccess) private var sensitiveAccess

    private var folderID: UUID? {
        guard case .folder(let id) = area else { return nil }
        return id
    }

    private var showsRecentlyDeleted: Bool { query.isEmpty && area == .recentlyDeleted }
    private var showsStack: Bool { query.isEmpty && area == .stack }
    private var isSelecting: Bool { selectedIDs != nil }

    private var sidebarSelection: Binding<Area?> {
        Binding(get: { area }, set: { destination in
            guard let destination, destination != area else { return }
            showArea(destination)
        })
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { session.selectedMemoryID },
            set: { id in
                guard id != session.selectedMemoryID else { return }
                session.selectedMemoryID = id
                session.clearSpotlightHighlight()
            }
        )
    }

    private var detailPath: Binding<[UUID]> {
        Binding(get: { session.selectedMemoryID.map { [$0] } ?? [] }, set: { path in
            selection.wrappedValue = path.last
        })
    }

    private var memories: [Memory] {
        if isSelecting, let folderID { return repository.results(for: query, folderID: folderID) }
        if area == .expired { return repository.expiredResults(for: query) }
        if !query.isEmpty { return repository.results(for: query) }
        if showsStack { return repository.stackMemories }
        guard let folderID else { return [] }
        return repository.results(for: "", folderID: folderID)
    }

    private var isEmptyLibrary: Bool {
        folderID == MemoryFolders.generalID && query.isEmpty && repository.results(for: "").isEmpty
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack(path: detailPath) {
                areaContent
                    .navigationDestination(for: UUID.self) { id in
                        if repository.memory(id: id)?.isDeleted == true {
                            ContentUnavailableView("Memory Not Found", systemImage: "info.circle")
                        } else {
                            MemoryDetailView(
                                repository: repository, memoryID: id, highlight: session.highlight(for: id),
                                narrowsActions: true
                            )
                            .id(id)
                        }
                    }
            }
            .frame(minWidth: 270)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $query, isPresented: $isSearching, placement: .toolbar, prompt: "Search memories")
        .focusedSceneValue(\.findMemories, { isSearching = true })
        .toolbar {
            ToolbarItem(placement: .navigation) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("New Folder", systemImage: "folder.badge.plus") { folderEditor = .create }
                Button("Toggle Sidebar", systemImage: "sidebar.left") {
                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                }
                .labelStyle(.iconOnly)
            }
            ToolbarItem {
                Button("New Memory", systemImage: "plus") {
                    session.showMacCapture(folderID: folderID ?? MemoryFolders.generalID)
                }
            }
            if !isSelecting, !repository.expiredResults(for: "").isEmpty {
                ToolbarItem {
                    Menu("Manage Memories", systemImage: "ellipsis.circle") {
                        Button("Expired", systemImage: "clock") {
                            showArea(.expired)
                        }
                    }
                }
            }
            if let folderID, session.selectedMemoryID == nil, isSelecting || query.isEmpty {
                ToolbarItemGroup {
                    if let selectedIDs {
                        let selected = repository.results(for: "", folderID: folderID)
                            .filter { selectedIDs.contains($0.id) }
                        Text("\(selected.count) selected")
                            .foregroundStyle(.secondary)
                        FolderSelectionMenu(
                            repository: repository, folderID: folderID, selection: selected,
                            requestDeletion: { pendingDeletion = $0 },
                            onSuccess: { self.selectedIDs = nil },
                            onFailure: { changeFailed = true }
                        )
                        Button("Done") { self.selectedIDs = nil }
                    } else {
                        Button("Choose Memories", systemImage: "checkmark.circle") {
                            selection.wrappedValue = nil
                            selectedIDs = []
                        }
                        .labelStyle(.iconOnly)
                        .disabled(memories.isEmpty)
                    }
                }
            }
        }
        .sheet(item: $folderEditor) { mode in
            FolderEditorView(folders: repository.folders, mode: mode)
        }
        .onChange(of: repository.folders.custom.map(\.id)) { _, ids in
            if let folderID, folderID != MemoryFolders.generalID, !ids.contains(folderID) {
                showArea(.folder(MemoryFolders.generalID))
            }
        }
        .onChange(of: query) { _, query in
            if !query.isEmpty { selection.wrappedValue = nil }
        }
        .onChange(of: area) {
            selectedIDs = nil
        }
        .onChange(of: repository.stackMemories.map(\.id)) { _, ids in
            if showsStack, let id = selection.wrappedValue, !ids.contains(id) {
                selection.wrappedValue = nil
            }
        }
        .onChange(of: session.selectedMemoryID, initial: true) {
            if session.selectedMemoryID != nil { selectedIDs = nil }
            guard let id = session.selectedMemoryID, !memories.contains(where: { $0.id == id }),
                  let memory = repository.memory(id: id), !memory.isDeleted
            else { return }
            query = ""
            area = memory.isExpired(at: .now) ? .expired : .folder(repository.folders.folderID(for: id))
        }
        .onChange(of: session.pendingSearch, initial: true) { _, search in
            guard let search else { return }
            session.pendingSearch = nil
            area = nil
            query = search
            isSearching = true
        }
        .memoryDeletionAlert(for: $pendingDeletion) { ids in
            change {
                try repository.delete(ids: ids)
                selectedIDs = nil
            }
        }
        .folderDeletionAlert(for: $pendingFolderDeletion) { folder in
            change {
                try repository.deleteFolder(folder.id)
                if area == .folder(folder.id) { showArea(.folder(MemoryFolders.generalID)) }
            }
        }
        .emptyTrashAlert(isPresented: $isConfirmingEmptyTrash, repository: repository) { _ in changeFailed = true }
        .alert("Couldn’t save", isPresented: $changeFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    private func showArea(_ destination: Area) {
        selection.wrappedValue = nil
        query = ""
        isSearching = false
        area = destination
    }

    private var sidebar: some View {
        let counts = repository.activeMemoryCountsByFolder
        let deletedCount = repository.deletedMemories.count
        return List(selection: sidebarSelection) {
            folderRow(
                Text("General"), area: .folder(MemoryFolders.generalID), count: counts[MemoryFolders.generalID, default: 0]
            )
            ForEach(repository.folders.custom) { folder in
                folderRow(Text(folder.name), area: .folder(folder.id), count: counts[folder.id, default: 0])
                    .contextMenu {
                        FolderMenuActions(
                            rename: { folderEditor = .rename(folder.id) },
                            delete: { pendingFolderDeletion = folder }
                        )
                    }
            }
            folderRow(Text("Stack"), symbol: "square.stack", area: .stack, count: repository.stackMemories.count)
            if deletedCount > 0 || area == .recentlyDeleted {
                folderRow(Text("Recently Deleted"), symbol: "trash", area: .recentlyDeleted, count: deletedCount)
                    .contextMenu {
                        if deletedCount > 0 {
                            Button("Empty Trash", systemImage: "trash", role: .destructive) { isConfirmingEmptyTrash = true }
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, LibrarySidebarLabel.rowHeight)
        .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 300)
    }

    private func folderRow(_ title: Text, symbol: String = "folder", area: Area, count: Int) -> some View {
        LibrarySidebarLabel(title: title, symbol: symbol, count: count)
            .listRowInsets(.vertical, 0)
            .tag(area)
    }

    @ViewBuilder
    private var areaContent: some View {
        if showsRecentlyDeleted {
            RecentlyDeletedView(repository: repository)
        } else if showsStack {
            MemoryStackView(repository: repository, selection: selection)
        } else if isEmptyLibrary {
            ScrollView {
                SpotlightGuide { session.showMacCapture() }
                    .padding(24)
            }
            .navigationTitle(listTitle)
        } else if area != nil || !query.isEmpty {
            memoryList
        } else {
            ContentUnavailableView("Select a Folder", systemImage: "folder")
        }
    }

    private var memoryList: some View {
        let results = memories
        return List(selection: isSelecting ? nil : selection) {
            if groupsByCategory, area != .expired, results.contains(where: { $0.category != nil }) {
                ForEach(results.groupedByCategory()) { section in
                    Section {
                        rows(section.memories)
                    } header: {
                        if let category = section.category {
                            category.label
                        } else {
                            Text("No Category")
                        }
                    }
                }
            } else {
                rows(results)
            }
        }
        .navigationTitle(listTitle)
        .overlay {
            if results.isEmpty {
                if !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if folderID != nil {
                    ContentUnavailableView("No Memories", systemImage: "folder")
                }
            }
        }
    }

    private var listTitle: Text {
        switch area {
        case .folder(let id): repository.folders.title(for: id)
        case .stack: Text("Stack")
        case .expired: Text("Expired")
        case .recentlyDeleted: Text("Recently Deleted")
        case nil: Text("Mindrop")
        }
    }

    private func rows(_ memories: [Memory]) -> some View {
        ForEach(memories) { memory in
            if isSelecting {
                selectionRow(memory)
            } else {
                MacMemoryActionsRow {
                    MacMemoryRow(memory: memory, query: query, isSelected: session.selectedMemoryID == memory.id)
                } actions: {
                    if sensitiveAccess.canShow(memory) {
                        Button("Copy") { Clipboard.copy(memory.value) }
                    }
                    if repository.isEligibleForStack(memory), !repository.isInStack(memory.id) {
                        Button("Add to Stack", systemImage: "square.stack") {
                            change { try repository.setStackMembership([memory.id], included: true) }
                        }
                    }
                    if memory.isExpired(at: .now) {
                        Button("Recover") { change { try repository.setExpiry(nil, for: memory) } }
                    }
                    if !repository.folders.custom.isEmpty {
                        let source = repository.folders.folderID(for: memory.id)
                        MoveToFolderMenu(folders: repository.folders, sourceFolderID: source) { id in
                            change { try repository.move(memory, to: id) }
                        }
                    }
                    Button("Delete", role: .destructive) { pendingDeletion = [memory] }
                }
                .tag(memory.id)
            }
        }
    }

    private func selectionRow(_ memory: Memory) -> some View {
        let isSelected = selectedIDs?.contains(memory.id) == true
        return Button {
            if isSelected {
                selectedIDs?.remove(memory.id)
            } else {
                selectedIDs?.insert(memory.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(.folderAccent) : .secondary)
                    .accessibilityHidden(true)
                MacMemoryRow(memory: memory)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func change(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            changeFailed = true
        }
    }
}

struct MacMemoryActionsRow<RowContent: View, Actions: View>: View {
    @ViewBuilder let rowContent: () -> RowContent
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack {
            rowContent()
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                actions()
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .contextMenu { actions() }
    }
}

struct MacMemoryRow: View {
    let memory: Memory
    var query = ""
    var isSelected = false

    @Environment(\.sensitiveAccess) private var sensitiveAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                HighlightedText(memory.keyword, query: query, highlightsBackground: !isSelected)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if memory.isSensitive { SensitiveBadge() }
            }
            if sensitiveAccess.canShow(memory) {
                HighlightedText(memory.value, query: query, highlightsBackground: !isSelected)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
