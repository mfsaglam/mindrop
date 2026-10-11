import CoreSpotlight
import Foundation

/// Resolves a tapped Spotlight result back to the memory it represents.
///
/// Takes the raw activity fields rather than an `NSUserActivity` so the routing rule
/// — including the cases where it must refuse — is unit-testable.
public enum SpotlightRouter {
    public static let activityType = CSSearchableItemActionType

    public static func memoryID(activityType: String, userInfo: [AnyHashable: Any]?) -> UUID? {
        guard activityType == Self.activityType,
              let identifier = userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return nil }
        return UUID(uuidString: identifier)
    }
}
