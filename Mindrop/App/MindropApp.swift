import MindropCore
import SwiftUI
import UIKit

@main
struct MindropApp: App {
    @State private var session = MindropSession()

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
        }
    }
}

/// Owns the repository, the navigation path and the Spotlight deep link.
@MainActor
@Observable
final class MindropSession {
    enum Phase {
        case loading
        case ready(MemoryRepository)
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    /// Back at the list, a highlight from Spotlight has served its purpose.
    var path: [UUID] = [] {
        didSet { if path.isEmpty { spotlightHighlight = nil } }
    }
    /// A search carried on from Spotlight ("Search in Mindrop"), for the list to show.
    /// The list clears it once shown.
    var pendingSearch: String?
    /// What was typed in Spotlight before the memory on screen was tapped, when Spotlight
    /// passes it along, so the detail screen can mark it.
    private(set) var spotlightHighlight: (memoryID: UUID, query: String)?
    #if DEBUG
    /// The last thing Spotlight handed the app, keys only, for the experiments screen:
    /// whether a tapped result carries the typed text is documented nowhere.
    private(set) var lastSpotlightActivity: (type: String, keys: [String])?
    #endif
    let sensitiveAccess = SensitiveAccess()
    private(set) var cloudSync: CloudSync?

    init() {
        // Started here as well as by the first screen: a push from iCloud can launch the
        // app in the background, where no screen appears to start it.
        Task { await start() }
    }

    /// What was asked of Apple Intelligence this launch. Debug builds only: it holds
    /// keywords and the start of each value.
    #if DEBUG
    let categorizationLog: CategorizationLog? = CategorizationLog()
    #else
    let categorizationLog: CategorizationLog? = nil
    #endif

    private var repository: MemoryRepository? {
        guard case .ready(let repository) = phase else { return nil }
        return repository
    }

    func start() async {
        guard case .loading = phase else { return }
        do {
            let repository = try MemoryRepository.live(
                categorizer: AppleIntelligenceCategorizer(log: categorizationLog),
                spotlightExtras: Self.spotlightExtras
            )
            try repository.load()
            try? repository.purge()
            // Show the list first: reconciling the Spotlight index can take seconds.
            phase = .ready(repository)
            startCloudSync(for: repository)
            repository.categorizePending()
            await repository.resumeSpotlightSync()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Picks up memories the share extension added while the app was in the background,
    /// and categorises them, since the extension does not. Also where expired memories
    /// past their 7 days are deleted for good.
    func refresh() {
        try? repository?.load()
        try? repository?.purge()
        repository?.categorizePending()
        cloudSync?.sendLocalChanges()
        if let cloudSync { Task { await cloudSync.fetchChanges() } }
    }

    /// On unless the user turned it off in Settings.
    private var syncsWithICloud: Bool {
        UserDefaults.standard.object(forKey: Preference.syncsWithICloud) as? Bool ?? true
    }

    /// Follows the Settings switch.
    func syncPreferenceChanged() {
        if syncsWithICloud { cloudSync?.start() } else { cloudSync?.stop() }
    }

    private func startCloudSync(for repository: MemoryRepository) {
        guard let cloudSync = try? CloudSync.live(repository: repository) else { return }
        self.cloudSync = cloudSync
        repository.onLocalChange = { [weak cloudSync] in cloudSync?.sendLocalChanges() }
        // Lets iCloud wake the app when another device changes something.
        UIApplication.shared.registerForRemoteNotifications()
        if syncsWithICloud { cloudSync.start() }
    }

    /// Opens the memory behind a tapped Spotlight result, without animating in from
    /// the list first, so the detail screen is what the user sees. "Search in Mindrop"
    /// goes back to the list, searching for what was typed.
    func open(activity: NSUserActivity) {
        #if DEBUG
        lastSpotlightActivity = (activity.activityType, (activity.userInfo ?? [:]).keys.map { "\($0)" }.sorted())
        #endif
        switch SpotlightRouter.destination(activityType: activity.activityType, userInfo: activity.userInfo) {
        case .memory(let id, let query):
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                path = [id]
            }
            spotlightHighlight = query.map { (id, $0) }
        case .search(let query):
            path = []
            pendingSearch = query
        case nil:
            break
        }
    }

    /// What was typed in Spotlight, if the memory was opened from there with it.
    func highlight(for memoryID: UUID) -> String? {
        spotlightHighlight?.memoryID == memoryID ? spotlightHighlight?.query : nil
    }

    /// What only the app can give Spotlight. Locating addresses is a Debug-only
    /// experiment: it sends them to Apple Maps.
    private static var spotlightExtras: SpotlightExtras {
        #if DEBUG
        SpotlightExtras(categoryIcons: SpotlightIcons.make(), locate: { await AddressLocator.shared.locate($0) })
        #else
        SpotlightExtras(categoryIcons: SpotlightIcons.make())
        #endif
    }
}
