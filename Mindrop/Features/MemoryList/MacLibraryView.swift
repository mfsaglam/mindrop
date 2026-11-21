#if os(macOS)
import MindropCore
import SwiftUI

struct MacLibraryView: View {
    private enum Area: Hashable {
        case folder(UUID)
        case expired
        case recentlyDeleted
    }

    let repository: MemoryRepository
    let session: MindropSession

    @State private var area: Area?
    @State private var query = ""
    @State private var isSearching = false
    @State private var pendingDeletion: Memory?
    @State private var changeFailed = false
    @State private var showsNewFolder = false
    @AppStorage(Preference.groupsByCategory) private var groupsByCategory = true
    @Environment(\.sensitiveAccess) private var sensitiveAccess

    private var folderID: UUID? {
        guard case .folder(let id) = area else { return nil }
        return id
    }

    private var showsRecentlyDeleted: Bool { query.isEmpty && area == .recentlyDeleted }

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
        if area == .expired { return repository.expiredResults(for: query) }
        if !query.isEmpty { return repository.results(for: query) }
        guard let folderID else { return [] }
        return repository.results(for: "", folderID: folderID)
    }

    private var isEmptyLibrary: Bool {
        folderID == MemoryFolders.generalID && query.isEmpty && repository.results(for: "").isEmpty
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $area) {
                folderRow(MemoryFolders.generalID)
                ForEach(repository.folders.custom) { folder in
                    folderRow(folder.id)
                }
                if !repository.deletedMemories.isEmpty || area == .recentlyDeleted {
                    Label("Recently Deleted", systemImage: "trash")
                        .tag(Area.recentlyDeleted)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Mindrop")
            .navigationSplitViewColumnWidth(min: 155, ideal: 175, max: 225)
        } content: {
            Group {
                if showsRecentlyDeleted {
                    RecentlyDeletedView(repository: repository)
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
            if !repository.expiredResults(for: "").isEmpty {
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
        }
        .sheet(isPresented: $showsNewFolder) {
            NewFolderView(folders: repository.folders)
        }
        .onChange(of: area) {
            if area == .recentlyDeleted {
                query = ""
                isSearching = false
            }
            if let id = selection.wrappedValue, !memories.contains(where: { $0.id == id }) {
                selection.wrappedValue = nil
            }
        }
        .onChange(of: session.selectedMemoryID, initial: true) {
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
        .alert(
            Text("Delete “\(pendingDeletion?.keyword ?? "")”?"),
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { memory in
            Button("Delete", role: .destructive) { change { try repository.delete(ids: [memory.id]) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It will be removed from Spotlight and kept in Recently Deleted for 30 days.")
        }
        .alert("Couldn’t save", isPresented: $changeFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    private func folderRow(_ id: UUID) -> some View {
        Label {
            repository.folders.title(for: id)
        } icon: {
            Image(systemName: "folder")
                .foregroundStyle(Color(.folderAccent))
        }
        .tag(Area.folder(id))
    }

    private var memoryList: some View {
        let results = memories
        return List(selection: selection) {
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
        case .expired: Text("Expired")
        case .recentlyDeleted: Text("Recently Deleted")
        case nil: Text("Mindrop")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection.wrappedValue, repository.memory(id: id)?.isDeleted != true {
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
                        MoveToFolderMenu(folders: repository.folders, memoryID: memory.id) { id in
                            change { try repository.move(memory, to: id) }
                        }
                    }
                    Button("Delete", role: .destructive) { pendingDeletion = memory }
                }
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
