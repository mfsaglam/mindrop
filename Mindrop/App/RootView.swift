import MindropCore
import SwiftUI

struct RootView: View {
    let session: MindropSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                ProgressView()
            case .ready(let repository):
                NavigationStack(path: Binding(get: { session.path }, set: { session.path = $0 })) {
                    MemoryListView(repository: repository, categorizationLog: session.categorizationLog)
                        .navigationDestination(for: UUID.self) { id in
                            MemoryDetailView(repository: repository, memoryID: id)
                        }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Mindrop can’t open your memories", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            }
        }
        .environment(\.sensitiveAccess, session.sensitiveAccess)
        .task { await session.start() }
        .onContinueUserActivity(SpotlightRouter.activityType) { activity in
            session.open(activity: activity)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.refresh() }
            // Not on `.inactive`: the Face ID prompt itself makes the app inactive.
            if phase == .background { session.sensitiveAccess.lock() }
        }
    }
}
