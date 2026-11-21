import Foundation

/// Shared container configuration. The app and the share extension both write here,
/// which is what lets a memory saved from the share sheet exist without opening the app.
public enum AppGroup {
    public static let identifier = "group.mfsaglam.Mindrop"

    /// The shared container, or `nil` when the entitlement is missing.
    public static var containerURL: URL? {
        #if os(macOS)
        let fileManager = FileManager.default
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let container = support.appending(path: "Mindrop", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
            return container
        } catch {
            return nil
        }
        #else
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #endif
    }

    public static let memoriesFileName = "memories.json"
    public static let syncStateFileName = "spotlight-sync.json"
    public static let cloudSyncStateFileName = "cloud-sync.json"
}
