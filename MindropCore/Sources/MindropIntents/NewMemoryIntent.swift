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
        NewMemoryRequest.shared.request(scanning: false)
        return .result()
    }
}

/// Opens Mindrop on the camera, to scan a value: a router sticker, a parking ticket, a
/// Wi-Fi QR code. The editor follows, waiting for the keyword. Behind the Scan control, the
/// Action button and Siri ("Scan into Mindrop").
public struct ScanValueIntent: AppIntent {
    public static let title: LocalizedStringResource = "Scan into Mindrop"
    public static let description = IntentDescription("Opens Mindrop’s camera to scan the details of a new memory.")
    /// Always runs in the app, even when started from the control's extension.
    public static let openAppWhenRun = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        NewMemoryRequest.shared.request(scanning: true)
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
    /// The request came from Scan, so the editor opens on the camera.
    public private(set) var scans = false

    private init() {}

    public func request(scanning: Bool) {
        scans = scanning
        isPending = true
    }
}

/// Lets the app's and the extension's App Intents metadata include the intent defined here.
public struct MindropIntentsPackage: AppIntentsPackage {}
