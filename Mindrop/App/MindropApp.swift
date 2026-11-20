import MindropCore
import MindropIntents
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
struct MindropApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(HomeScreenActionAppDelegate.self) private var appDelegate
    #endif
    @State private var session = MindropSession()

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
        }
        #if os(macOS)
        .defaultSize(width: 760, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Memory") {
                    NewMemoryRequest.shared.request(scanning: false)
                }
                .keyboardShortcut("n")
            }
        }
        #endif

        #if os(macOS)
        Settings {
            Group {
                switch session.phase {
                case .loading:
                    ProgressView()
                case .ready(let repository):
                    SettingsView(repository: repository, session: session)
                case .failed:
                    ContentUnavailableView {
                        Label("Mindrop can’t open your memories", image: "ix.danger.linear")
                    } description: {
                        Text("Try closing Mindrop and opening it again.")
                    }
                }
            }
            .frame(minWidth: 480, idealWidth: 540, minHeight: 420, idealHeight: 520)
        }
        #endif
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
    let driveBackup = DriveMemoryBackup()
    private(set) var cloudSync: CloudSync?
    #if os(iOS)
    private let watchLink: WatchLink
    #endif

    init() {
        #if os(iOS)
        watchLink = WatchLink(syncsWithICloud: Self.syncsWithICloud)
        #endif
        // Started here as well as by the first screen: a push from iCloud can launch the
        // app in the background, where no screen appears to start it.
        Task { await start() }
        // Save to Mindrop writes through a repository of its own; the app may be on screen
        // (Siri over it, or Shortcuts beside it in Split View), so catch up straight away.
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: SaveMemoryIntent.didSave) {
                self?.refresh()
            }
        }
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
            #if os(iOS)
            watchLink.deliver { [weak self] memory in self?.takeFromWatch(memory) }
            #endif
            repository.categorizePending()
            await repository.resumeSpotlightSync()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Picks up memories the share extension added while the app was in the background,
    /// and categorises them, since the extension does not. Also where expired memories
    /// past their 7 days are deleted for good.
    func refresh(backsUpToDrive: Bool = false) {
        try? repository?.load()
        try? repository?.purge()
        repository?.categorizePending()
        cloudSync?.sendLocalChanges()
        Task {
            await cloudSync?.fetchChanges()
            guard backsUpToDrive, UserDefaults.standard.bool(forKey: Preference.automaticDriveBackup),
                  let repository,
                  let memories = try? repository.memoriesForBackup()
            else { return }
            try? await driveBackup.create(memories: memories, automatically: true)
        }
    }

    /// On unless the user turned it off in Settings.
    private static var syncsWithICloud: Bool {
        UserDefaults.standard.object(forKey: Preference.syncsWithICloud) as? Bool ?? true
    }

    /// Follows the Settings switch, here and on the Apple Watch.
    func syncPreferenceChanged() {
        if Self.syncsWithICloud { cloudSync?.start() } else { cloudSync?.stop() }
        #if os(iOS)
        watchLink.setSyncsWithICloud(Self.syncsWithICloud)
        #endif
    }

    #if os(iOS)
    /// A memory saved on the Apple Watch, taken in like one synced from another device:
    /// filed, indexed and categorised. It may have come through iCloud already, in which
    /// case nothing changes. Sent on to iCloud, since it may have come only from the watch.
    private func takeFromWatch(_ memory: Memory) {
        guard let repository else { return }
        do {
            try repository.applyRemote([memory], deletedIDs: [])
        } catch {
            // The watch has already let go of it; it stays lost only if storage is broken,
            // which the list would show anyway.
            return
        }
        cloudSync?.sendLocalChanges()
    }
    #endif

    private func startCloudSync(for repository: MemoryRepository) {
        guard let cloudSync = try? CloudSync.live(repository: repository) else { return }
        self.cloudSync = cloudSync
        repository.onLocalChange = { [weak cloudSync] in cloudSync?.sendLocalChanges() }
        // Lets iCloud wake the app when another device changes something.
        #if os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
        if Self.syncsWithICloud { cloudSync.start() }
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

    /// What only the app can give Spotlight, also used by Save to Mindrop. Locating addresses is a Debug-only
    /// experiment: it sends them to Apple Maps.
    static var spotlightExtras: SpotlightExtras {
        #if DEBUG
        SpotlightExtras(categoryIcons: SpotlightIcons.make(), locate: { await AddressLocator.shared.locate($0) })
        #else
        SpotlightExtras(categoryIcons: SpotlightIcons.make())
        #endif
    }
}
