#if os(macOS)
import MindropCore
import SwiftUI

struct MacLibraryView: View {
    private enum Area: Hashable {
        case all
        case category(MemoryCategory)
        case expired
        case recentlyDeleted
    }

    let repository: MemoryRepository
    let session: MindropSession

    @State private var area: Area? = .all
    @State private var query = ""
    @State private var isSearching = false
    @State private var pendingDeletion: Memory?
    @State private var changeFailed = false
    @AppStorage(Preference.groupsByCategory) private var groupsByCategory = true
    @Environment(\.sensitiveAccess) private var sensitiveAccess

    private var destination: Area { area ?? .all }

    private var selection: Binding<UUID?> {
        Binding(
            get: { session.path.last },
            set: { id in
                guard id != session.path.last else { return }
                session.path = id.map { [$0] } ?? []
                session.clearSpotlightHighlight()
            }
        )
    }

    private var memories: [Memory] {
        switch destination {
        case .all: repository.results(for: query)
        case .category(let category): repository.results(for: query, in: category)
        case .expired: repository.expiredResults(for: query)
        case .recentlyDeleted: []
        }
    }

    private var isEmptyLibrary: Bool {
        destination == .all && query.isEmpty && repository.results(for: "").isEmpty
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $area) {
                Label("All Memories", systemImage: "tray.full").tag(Area.all)
                ForEach(repository.categoriesInUse, id: \.self) { category in
                    let item = Area.category(category)
                    Label {
                        Text(category.title)
                    } icon: {
                        Image(category.symbolName)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(
                                destination == item ? AnyShapeStyle(.foreground) : AnyShapeStyle(category.tint)
                            )
                    }
                    .tag(item)
                }
                if !repository.expiredResults(for: "").isEmpty {
                    Label("Expired", systemImage: "clock").tag(Area.expired)
                }
                if !repository.deletedMemories.isEmpty {
                    Label("Recently Deleted", systemImage: "trash").tag(Area.recentlyDeleted)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Mindrop")
            .navigationSplitViewColumnWidth(min: 155, ideal: 175, max: 225)
        } content: {
            Group {
                if destination == .recentlyDeleted {
                    RecentlyDeletedView(repository: repository)
                } else {
                    memoryList
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
                Button("New Memory", systemImage: "plus") { session.showMacCapture() }
            }
        }
        .onChange(of: isSearching) {
            if isSearching, destination == .recentlyDeleted { area = .all }
        }
        .onChange(of: area) {
            if let id = selection.wrappedValue, !memories.contains(where: { $0.id == id }) {
                selection.wrappedValue = nil
            }
        }
        .onChange(of: session.path, initial: true) {
            guard let id = session.path.last, !memories.contains(where: { $0.id == id }),
                  let memory = repository.memory(id: id), !memory.isDeleted
            else { return }
            query = ""
            area = memory.isExpired(at: .now) ? .expired : .all
        }
        .onChange(of: session.pendingSearch, initial: true) { _, search in
            guard let search else { return }
            session.pendingSearch = nil
            area = .all
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

    private var memoryList: some View {
        List(selection: selection) {
            if groupsByCategory, destination == .all, !repository.categoriesInUse.isEmpty {
                ForEach(memories.groupedByCategory()) { section in
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
                rows(memories)
            }
        }
        .navigationTitle(listTitle)
        .overlay {
            if memories.isEmpty, !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private var listTitle: Text {
        switch destination {
        case .all: Text("All Memories")
        case .category(let category): Text(category.title)
        case .expired: Text("Expired")
        case .recentlyDeleted: Text("Recently Deleted")
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
        } else if destination != .recentlyDeleted {
            ContentUnavailableView("Select a Memory", systemImage: "text.alignleft")
        } else {
            Color.clear
        }
    }

    private func rows(_ memories: [Memory]) -> some View {
        ForEach(memories) { memory in
            MacMemoryRow(memory: memory, query: query, isSelected: session.path.last == memory.id)
                .tag(memory.id)
                .contextMenu {
                    if sensitiveAccess.canShow(memory) {
                        Button("Copy") { Clipboard.copy(memory.value) }
                    }
                    if memory.isExpired(at: .now) {
                        Button("Recover") { change { try repository.setExpiry(nil, for: memory) } }
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
