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

    @State private var area: Area?
    @State private var query = ""
    @State private var isSearching = false
    @State private var selectedIDs: Set<UUID>?
    @State private var pendingDeletion: [Memory] = []
    @State private var pendingFolderDeletion: MemoryFolder?
    @State private var changeFailed = false
    @State private var showsNewFolder = false
    @AppStorage(Preference.groupsByCategory) private var groupsByCategory = true
    @Environment(\.sensitiveAccess) private var sensitiveAccess

    private var folderID: UUID? {
        guard case .folder(let id) = area else { return nil }
        return id
    }

    private var showsRecentlyDeleted: Bool { query.isEmpty && area == .recentlyDeleted }
    private var showsStack: Bool { query.isEmpty && area == .stack }
    private var isSelecting: Bool { selectedIDs != nil }

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
        NavigationSplitView {
            List(selection: $area) {
                folderRow(Text("General"), area: .folder(MemoryFolders.generalID))
                folderRow(
                    Text("Stack"), symbol: "square.stack", area: .stack, count: repository.stackMemories.count
                )
                ForEach(repository.folders.custom) { folder in
                    folderRow(Text(folder.name), area: .folder(folder.id))
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingFolderDeletion = folder
                            } label: {
                                Label("Delete Folder", systemImage: "trash")
                            }
                        }
                }
                if !repository.deletedMemories.isEmpty || area == .recentlyDeleted {
                    folderRow(Text("Recently Deleted"), symbol: "trash", area: .recentlyDeleted)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Mindrop")
            .navigationSplitViewColumnWidth(min: 155, ideal: 175, max: 225)
        } content: {
            Group {
                if showsRecentlyDeleted {
                    RecentlyDeletedView(repository: repository)
                } else if showsStack {
                    MemoryStackView(repository: repository, selection: selection)
                } else if area != nil || !query.isEmpty {
                    memoryList
                } else {
                    ContentUnavailableView("Select a Folder", systemImage: "folder")
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 255)
        } detail: {
            detail
                .frame(minWidth: 270)
        }
        .searchable(text: $query, isPresented: $isSearching, placement: .toolbar, prompt: "Search memories")
        .focusedSceneValue(\.findMemories, { isSearching = true })
        .toolbar {
            ToolbarItem {
                Button("New Folder", systemImage: "folder.badge.plus") { showsNewFolder = true }
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
                            query = ""
                            isSearching = false
                            area = .expired
                        }
                    }
                }
            }
            if let folderID, isSelecting || query.isEmpty {
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
        .sheet(isPresented: $showsNewFolder) {
            NewFolderView(folders: repository.folders)
        }
        .onChange(of: area) {
            selectedIDs = nil
            if area == .recentlyDeleted || area == .stack {
                query = ""
                isSearching = false
            }
            if let id = selection.wrappedValue, !memories.contains(where: { $0.id == id }) {
                selection.wrappedValue = nil
            }
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
                if area == .folder(folder.id) { area = nil }
            }
        }
        .alert("Couldn’t save", isPresented: $changeFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    private func folderRow(_ title: Text, symbol: String = "folder", area: Area, count: Int? = nil) -> some View {
        HStack {
            Label {
                title
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(area == .recentlyDeleted ? Color.primary : Color(.folderAccent))
            }
            if let count {
                Spacer(minLength: 4)
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Memory Count"))
                    .accessibilityValue(Text(count, format: .number))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(.rect)
        .listRowInsets(.vertical, 0)
        .tag(area)
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

    @ViewBuilder
    private var detail: some View {
        if isSelecting {
            Color.clear
        } else if let id = selection.wrappedValue, repository.memory(id: id)?.isDeleted != true {
            MemoryDetailView(repository: repository, memoryID: id, highlight: session.highlight(for: id))
                .id(id)
        } else if isEmptyLibrary {
            ScrollView {
                SpotlightGuide { session.showMacCapture() }
                    .padding(24)
            }
        } else if !showsRecentlyDeleted, area != nil || !query.isEmpty {
            ContentUnavailableView("Select a Memory", systemImage: "text.alignleft")
        } else {
            Color.clear
        }
    }

    private func rows(_ memories: [Memory]) -> some View {
        ForEach(memories) { memory in
            if isSelecting {
                selectionRow(memory)
            } else {
                MacMemoryRow(memory: memory, query: query, isSelected: session.selectedMemoryID == memory.id)
                    .tag(memory.id)
                    .contextMenu {
                        if sensitiveAccess.canShow(memory) {
                            Button("Copy") { Clipboard.copy(memory.value) }
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
