#if canImport(CoreSpotlight)
import CoreSpotlight
import Foundation

/// Resolves what Spotlight handed the app: a tapped result, or a search to carry on.
///
/// Takes the raw activity fields rather than an `NSUserActivity` so the routing rule
/// — including the cases where it must refuse — is unit-testable.
public enum SpotlightRouter {
    public static let activityType = CSSearchableItemActionType
    /// Spotlight's "Search in Mindrop", offered because Info.plist sets
    /// `CoreSpotlightContinuation`.
    public static let searchActivityType = CSQueryContinuationActionType

    public enum Destination: Equatable, Sendable {
        /// A tapped result. `query` is what was typed, if Spotlight passed it along:
        /// documented only for a continued search, so it may well be missing.
        case memory(UUID, query: String?)
        /// "Search in Mindrop": the list, searching for what was typed.
        case search(String)
    }

    public static func destination(activityType: String, userInfo: [AnyHashable: Any]?) -> Destination? {
        switch activityType {
        case Self.activityType:
            guard let identifier = userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let id = UUID(uuidString: identifier)
            else { return nil }
            return .memory(id, query: query(in: userInfo))
        case searchActivityType:
            return query(in: userInfo).map(Destination.search)
        default:
            return nil
        }
    }

    public static func memoryID(activityType: String, userInfo: [AnyHashable: Any]?) -> UUID? {
        guard case .memory(let id, _) = destination(activityType: activityType, userInfo: userInfo) else { return nil }
        return id
    }

    private static func query(in userInfo: [AnyHashable: Any]?) -> String? {
        guard let query = (userInfo?[CSSearchQueryString] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty
        else { return nil }
        return query
    }
}
#endif
