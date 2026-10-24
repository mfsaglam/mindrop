import AppIntents
import MindropIntents

/// Lets the app's App Intents metadata include the intents from the package.
struct MindropAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [MindropIntentsPackage.self] }
}

/// Offered with no setup: under Mindrop when choosing what the Action button does, in the
/// Shortcuts app, and to Siri.
struct MindropShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewMemoryIntent(),
            phrases: [
                "New memory in \(.applicationName)",
                "Add a memory to \(.applicationName)",
            ],
            shortTitle: "New Memory",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: ScanValueIntent(),
            phrases: [
                "Scan with \(.applicationName)",
                "Scan something with \(.applicationName)",
            ],
            shortTitle: "Scan",
            systemImageName: "text.viewfinder"
        )
    }
}
