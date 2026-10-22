import Foundation

/// The choices behind what Mindrop hands Spotlight that are still open questions, to be
/// settled on a real iPhone: the simulator's Spotlight drops every third-party item.
///
/// Release builds always use `shipping`. Debug builds read the Spotlight Experiments
/// screen's choices from the App Group, so the share extension indexes the same way.
public struct SpotlightOptions: Codable, Equatable, Sendable {
    /// The category's icon in place of Mindrop's on each result, with Mindrop's as a
    /// small badge. Shipped: it tells results apart at a glance.
    public var showsCategoryIcon: Bool
    /// A phone number in a Contacts or Family & People memory, handed to Spotlight for its
    /// Call button. Shipped: the number is already on the result's line.
    public var offersCall: Bool
    /// An address's coordinates, for Spotlight's Directions button. Finding them goes
    /// through Apple Maps, so the address leaves the device: not shipped.
    public var offersDirections: Bool

    public init(
        showsCategoryIcon: Bool = true,
        offersCall: Bool = true,
        offersDirections: Bool = false
    ) {
        self.showsCategoryIcon = showsCategoryIcon
        self.offersCall = offersCall
        self.offersDirections = offersDirections
    }

    /// Written out by hand so that choices stored by an earlier experiment screen, with
    /// fields since dropped or added, still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let shipping = SpotlightOptions.shipping
        showsCategoryIcon = try container.decodeIfPresent(Bool.self, forKey: .showsCategoryIcon) ?? shipping.showsCategoryIcon
        offersCall = try container.decodeIfPresent(Bool.self, forKey: .offersCall) ?? shipping.offersCall
        offersDirections = try container.decodeIfPresent(Bool.self, forKey: .offersDirections) ?? shipping.offersDirections
    }

    public static let shipping = SpotlightOptions()

    /// What indexing uses right now.
    public static var current: SpotlightOptions {
        #if DEBUG
        guard let data = defaults?.data(forKey: defaultsKey),
              let options = try? JSONDecoder().decode(SpotlightOptions.self, from: data)
        else { return .shipping }
        return options
        #else
        return .shipping
        #endif
    }

    #if DEBUG
    /// Stores the experiment's choices. The caller reindexes.
    public static func setCurrent(_ options: SpotlightOptions) {
        defaults?.set(try? JSONEncoder().encode(options), forKey: defaultsKey)
    }
    #endif

    private static let defaultsKey = "spotlightOptions"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }
}
