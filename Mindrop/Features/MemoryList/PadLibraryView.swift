#if os(iOS)
import MindropCore
import MindropIntents
import SwiftUI

struct PadLibraryView: View {
    private enum SidebarSheet: Hashable, Identifiable {
        case folderEditor(FolderEditorView.Mode)
        case settings

        var id: Self { self }
    }

    let repository: MemoryRepository
    let session: MindropSession

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var folderPullFeedback = FolderPullFeedback()
    @State private var stackPullFeedback = FolderPullFeedback()
    @State private var recentlyDeletedPullFeedback = FolderPullFeedback()
    @State private var sheet: SidebarSheet?
    @State private var pendingFolderDeletion: MemoryFolder?
    @State private var isConfirmingEmptyTrash = false
    @State private var changeFailed = false

    private let newMemoryRequest = NewMemoryRequest.shared
    private static let sidebarRowHeight: CGFloat = 44

    private var general: LibraryRoute { .folder(MemoryFolders.generalID) }

    /// The first route selects the sidebar. Any following memory route belongs to the right column.
    private var area: LibraryRoute {
        switch session.path.first {
        case .memory(let id): .folder(repository.folders.folderID(for: id))
        case let route?: route
        case nil: general
        }
    }

    private var sidebarSelection: Binding<LibraryRoute?> {
        Binding(get: { area == .search ? nil : area }, set: { route in
            if let route { select(route) }
        })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            sidebar
        } detail: {
            detail(for: area)
                .id(area)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: session.path, initial: true) { _, path in
            if path.isEmpty || path.first != area {
                session.path = [area] + path
            }
            compactColumn = .detail
        }
        .onChange(of: repository.folders.custom.map(\.id)) { _, ids in
            if case .folder(let id) = area, area != general, !ids.contains(id) { select(general) }
        }
        .onChange(of: newMemoryRequest.isPending, initial: true) { _, pending in
            guard pending else { return }
            sheet = nil
            switch area {
            case .folder, .search: select(area)
            case .stack, .recentlyDeleted, .memory: select(general)
            }
        }
    }

    private func select(_ route: LibraryRoute) {
        if session.path != [route] { session.path = [route] }
        compactColumn = .detail
    }

    private var sidebar: some View {
        let counts = repository.results(for: "").reduce(into: [UUID: Int]()) { counts, memory in
            counts[repository.folders.folderID(for: memory.id), default: 0] += 1
        }
        let deletedCount = repository.deletedMemories.count
        return List(selection: sidebarSelection) {
            sidebarButton(Text("General"), symbol: "folder", count: counts[MemoryFolders.generalID, default: 0], route: general)
            ForEach(repository.folders.custom) { folder in
                let route = LibraryRoute.folder(folder.id)
                Menu {
                    FolderMenuActions(
                        rename: { sheet = .folderEditor(.rename(folder.id)) },
                        delete: { pendingFolderDeletion = folder }
                    )
                } label: {
                    SidebarLabel(title: Text(folder.name), symbol: "folder", count: counts[folder.id, default: 0])
                } primaryAction: {
                    select(route)
                }
                .buttonStyle(.plain)
                .menuOrder(.fixed)
                .listRowInsets(.vertical, 0)
                .tag(route)
            }
            sidebarButton(Text("Stack"), symbol: "square.stack", count: repository.stackMemories.count, route: .stack)
            if deletedCount > 0 {
                Menu {
                    Button("Empty Trash", systemImage: "trash", role: .destructive) { isConfirmingEmptyTrash = true }
                } label: {
                    SidebarLabel(title: Text("Recently Deleted"), symbol: "trash", count: deletedCount)
                } primaryAction: {
                    select(.recentlyDeleted)
                }
                .buttonStyle(.plain)
                .listRowInsets(.vertical, 0)
                .tag(LibraryRoute.recentlyDeleted)
            } else if area == .recentlyDeleted {
                sidebarButton(Text("Recently Deleted"), symbol: "trash", count: 0, route: .recentlyDeleted)
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, Self.sidebarRowHeight)
        .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 300)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { sheet = .settings }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Folder", systemImage: "folder.badge.plus") { sheet = .folderEditor(.create) }
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .folderEditor(let mode): FolderEditorView(folders: repository.folders, mode: mode)
            case .settings: SettingsView(repository: repository, session: session)
            }
        }
        .folderDeletionAlert(for: $pendingFolderDeletion) { folder in
            do { try repository.deleteFolder(folder.id) } catch { changeFailed = true }
        }
        .emptyTrashAlert(isPresented: $isConfirmingEmptyTrash, repository: repository) { _ in changeFailed = true }
        .alert("Couldn’t save", isPresented: $changeFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    private func sidebarButton(_ title: Text, symbol: String, count: Int, route: LibraryRoute) -> some View {
        Button { select(route) } label: {
            SidebarLabel(title: title, symbol: symbol, count: count)
        }
        .buttonStyle(.plain)
        .listRowInsets(.vertical, 0)
        .tag(route)
    }

    private struct SidebarLabel: View {
        let title: Text
        let symbol: String
        let count: Int

        @Environment(\.self) private var environment
        @Environment(\.backgroundProminence) private var backgroundProminence

        var body: some View {
            let highlightForeground = backgroundProminence == .increased
                ? Color.accentColor.contrastingForeground(in: environment)
                : nil

            HStack {
                Label {
                    title.foregroundStyle(highlightForeground ?? .primary)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(highlightForeground ?? Color(.folderAccent))
                }
                Spacer(minLength: 4)
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(highlightForeground ?? .secondary)
                    .accessibilityLabel(Text("Memory Count"))
                    .accessibilityValue(Text(count, format: .number))
            }
            .frame(minHeight: PadLibraryView.sidebarRowHeight)
            .contentShape(.rect)
        }
    }

    private func detail(for route: LibraryRoute) -> some View {
        ZStack(alignment: .top) {
            NavigationStack(path: memoryPath(for: route)) {
                areaContent(for: route)
                    .navigationDestination(for: LibraryRoute.self) { destination in
                        if case .memory(let id) = destination {
                            MemoryDetailView(repository: repository, memoryID: id, highlight: session.highlight(for: id))
                                .memoryScreenBackground(usesGradient: true)
                        }
                    }
            }
            if session.path.last == route, let feedback = pullFeedback(for: route) {
                FolderPullIndicator(feedback: feedback)
                    .id(ObjectIdentifier(feedback))
                    .zIndex(1)
            }
        }
    }

    private func memoryPath(for route: LibraryRoute) -> Binding<[LibraryRoute]> {
        Binding(get: {
            guard area == route else { return [] }
            return session.path.filter { if case .memory = $0 { true } else { false } }
        }, set: { memories in
            guard area == route else { return }
            let path = [route] + memories
            if session.path != path { session.path = path }
        })
    }

    @ViewBuilder
    private func areaContent(for route: LibraryRoute) -> some View {
        switch route {
        case .folder(let id): memoryList(folderID: id)
        case .search: memoryList(folderID: nil)
        case .stack:
            MemoryStackView(
                repository: repository, pullFeedback: stackPullFeedback, isActiveScreen: session.path.last == route,
                openMemory: { session.path.append(.memory($0)) }
            )
        case .recentlyDeleted:
            RecentlyDeletedView(
                repository: repository, pullFeedback: recentlyDeletedPullFeedback, isActiveScreen: session.path.last == route
            )
        case .memory:
            memoryList(folderID: MemoryFolders.generalID)
        }
    }

    private func memoryList(folderID: UUID?) -> some View {
        MemoryListView(
            repository: repository, session: session, folderID: folderID, isSplitColumn: true,
            folderPullFeedback: folderPullFeedback
        )
        .memoryScreenBackground(usesGradient: true)
    }

    private func pullFeedback(for route: LibraryRoute) -> FolderPullFeedback? {
        switch route {
        case .folder: folderPullFeedback
        case .stack: stackPullFeedback
        case .recentlyDeleted: recentlyDeletedPullFeedback
        case .memory, .search: nil
        }
    }
}
#endif
