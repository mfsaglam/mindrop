import MindropCore
import SwiftUI

enum LibraryRoute: Hashable {
    case folder(UUID)
    case memory(UUID)
    case stack
    case recentlyDeleted
}

struct RootView: View {
    let session: MindropSession
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
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
        case .memory: nil
        }
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
                ZStack(alignment: .top) {
                    NavigationStack(path: Binding(get: { session.path }, set: { session.path = $0 })) {
                        MemoryListView(repository: repository, session: session, folderPullFeedback: libraryPullFeedback)
                            .memoryScreenBackground(usesGradient: true)
                            .navigationDestination(for: LibraryRoute.self) { route in
                                switch route {
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
                                        isActiveScreen: session.path.last == .stack
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
                .task {
                    if scenePhase == .active { session.refreshOnActivation() }
                }
                #endif
            case .failed:
                ContentUnavailableView {
                    Label("Mindrop can’t open your memories", image: "ix.danger.linear")
                } description: {
                    Text("Try closing Mindrop and opening it again.")
                }
            }
        }
        .environment(\.sensitiveAccess, session.sensitiveAccess)
        .task { await session.start() }
        .onContinueUserActivity(SpotlightRouter.activityType) { activity in
            session.open(activity: activity)
        }
        .onContinueUserActivity(SpotlightRouter.searchActivityType) { activity in
            session.open(activity: activity)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.refreshOnActivation() }
            // Not on `.inactive`: the Face ID prompt itself makes the app inactive.
            if phase == .background { session.sensitiveAccess.lock() }
        }
    }
}
