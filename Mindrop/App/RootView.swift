import MindropCore
import SwiftUI
#if os(iOS)
import MindropWidgetData
import UIKit
#endif

enum LibraryRoute: Hashable {
    case folder(UUID)
    case memory(UUID)
    case stack
    case recentlyDeleted
    case search
}

struct RootView: View {
    let session: MindropSession
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesSplitLibrary: Bool {
        let idiom = UIDevice.current.userInterfaceIdiom
        if idiom == .pad { return true }
        guard #available(iOS 27.1, *), idiom == .phone else { return false }
        // The Duo's inner display is regular width. The outer display is compact.
        return horizontalSizeClass == .regular
    }
    #endif

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                ProgressView()
            case .ready(let repository):
                #if os(macOS)
                MacLibraryView(repository: repository, session: session)
                    .frame(minWidth: 660, minHeight: 420)
                    .task {
                        if scenePhase == .active { session.refreshOnActivation() }
                    }
                #else
                Group {
                    if usesSplitLibrary {
                        SplitLibraryView(repository: repository, session: session)
                    } else {
                        PhoneLibraryView(repository: repository, session: session)
                    }
                }
                .task {
                    if scenePhase == .active { session.refreshOnActivation() }
                }
                #endif
            case .failed:
                ContentUnavailableView {
                    Label("Mindrop can’t open your memories", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Try closing Mindrop and opening it again.")
                }
            }
        }
        .environment(\.sensitiveAccess, session.sensitiveAccess)
        .task { await session.start() }
        #if os(iOS)
        .onOpenURL { url in
            if url == StackWidgetSnapshot.stackURL { session.path = [.stack] }
        }
        #endif
        .onContinueUserActivity(SpotlightRouter.activityType) { activity in
            session.open(activity: activity)
        }
        .onContinueUserActivity(SpotlightRouter.searchActivityType) { activity in
            #if os(iOS)
            session.open(activity: activity, usesSplitLibrary: usesSplitLibrary)
            #else
            session.open(activity: activity)
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.refreshOnActivation() }
            // Not on `.inactive`: the Face ID prompt itself makes the app inactive.
            if phase == .background { session.sensitiveAccess.lock() }
        }
    }
}

#if os(iOS)
private struct PhoneLibraryView: View {
    let repository: MemoryRepository
    let session: MindropSession
    @State private var libraryPullFeedback = FolderPullFeedback()
    @State private var folderPullFeedback = FolderPullFeedback()
    @State private var stackPullFeedback = FolderPullFeedback()
    @State private var recentlyDeletedPullFeedback = FolderPullFeedback()

    private var activePullFeedback: FolderPullFeedback? {
        switch session.path.last {
        case nil: libraryPullFeedback
        case .folder: folderPullFeedback
        case .stack: stackPullFeedback
        case .recentlyDeleted: recentlyDeletedPullFeedback
        case .memory, .search: nil
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            NavigationStack(path: Binding(get: { session.path }, set: { session.path = $0 })) {
                MemoryListView(repository: repository, session: session, folderPullFeedback: libraryPullFeedback)
                    .memoryScreenBackground(usesGradient: true)
                    .navigationDestination(for: LibraryRoute.self) { route in
                        switch route {
                        case .search:
                            MemoryListView(
                                repository: repository, session: session, isGlobalSearch: true,
                                folderPullFeedback: libraryPullFeedback
                            )
                            .memoryScreenBackground(usesGradient: true)
                        case .folder(let id):
                            MemoryListView(
                                repository: repository, session: session, folderID: id,
                                folderPullFeedback: folderPullFeedback
                            )
                            .memoryScreenBackground(usesGradient: true)
                        case .memory(let id):
                            MemoryDetailView(repository: repository, memoryID: id, highlight: session.highlight(for: id))
                                .memoryScreenBackground(usesGradient: true)
                        case .stack:
                            MemoryStackView(
                                repository: repository, pullFeedback: stackPullFeedback,
                                isActiveScreen: session.path.last == .stack,
                                openMemory: { session.path.append(.memory($0)) }
                            )
                        case .recentlyDeleted:
                            RecentlyDeletedView(
                                repository: repository, pullFeedback: recentlyDeletedPullFeedback,
                                isActiveScreen: session.path.last == .recentlyDeleted
                            )
                        }
                    }
            }
            // The large navigation title stretches with the scroll view.
            if let activePullFeedback {
                FolderPullIndicator(feedback: activePullFeedback)
                    .id(ObjectIdentifier(activePullFeedback))
                    .zIndex(1)
            }
        }
        .onChange(of: repository.folders.custom.map(\.id)) { _, ids in
            guard let removedFolder = session.path.firstIndex(where: { route in
                guard case .folder(let id) = route else { return false }
                return id != MemoryFolders.generalID && !ids.contains(id)
            }) else { return }
            session.path.removeSubrange(removedFolder...)
        }
    }
}
#endif
