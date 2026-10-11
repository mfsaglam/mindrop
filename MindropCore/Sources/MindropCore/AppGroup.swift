import Foundation

/// Shared container configuration. The app and the share extension both write here,
/// which is what lets a memory saved from the share sheet exist without opening the app.
public enum AppGroup {
    public static let identifier = "group.mfsaglam.Mindrop"

    /// The shared container, or `nil` when the entitlement is missing.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static let memoriesFileName = "memories.json"
    public static let syncStateFileName = "spotlight-sync.json"
}
