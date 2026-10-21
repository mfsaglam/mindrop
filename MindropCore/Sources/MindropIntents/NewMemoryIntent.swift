import AppIntents
import Observation

/// Opens Mindrop on a blank editor. Behind the Control Center control, the Action button
/// and Siri ("New memory in Mindrop").
///
/// In a package of its own because the control's widget extension must contain the intent
/// too, and the share extensions, which link `MindropCore`, must not offer it.
public struct NewMemoryIntent: AppIntent {
    public static let title: LocalizedStringResource = "New Memory"
    public static let description = IntentDescription("Opens Mindrop ready to save a new memory.")
    /// Always runs in the app, even when started from the control's extension.
    public static let openAppWhenRun = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        NewMemoryRequest.shared.isPending = true
        return .result()
    }
}

/// Carries a request for the editor from an intent to the UI. The intent can run before the
/// list is on screen, so it leaves a flag rather than calling into a view.
@MainActor
@Observable
public final class NewMemoryRequest {
    public static let shared = NewMemoryRequest()

    public var isPending = false

    private init() {}
}

/// Lets the app's and the extension's App Intents metadata include the intent defined here.
public struct MindropIntentsPackage: AppIntentsPackage {}
