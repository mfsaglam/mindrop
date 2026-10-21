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
    var path: [UUID] = []
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
            let repository = try MemoryRepository.live(categorizer: AppleIntelligenceCategorizer(log: categorizationLog))
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
    /// the list first, so the detail screen is what the user sees.
    func open(activity: NSUserActivity) {
        guard let id = SpotlightRouter.memoryID(activityType: activity.activityType, userInfo: activity.userInfo)
        else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            path = [id]
        }
    }
}
