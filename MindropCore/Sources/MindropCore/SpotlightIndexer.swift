#if canImport(CoreSpotlight)
import CoreSpotlight
#endif
import Foundation
import UniformTypeIdentifiers

/// Indexing boundary, so synchronisation logic can be tested against a spy.
public protocol SpotlightIndexing: Sendable {
    func index(_ items: [SpotlightAttributes]) async throws
    func remove(ids: [UUID]) async throws
    /// Removes every memory Mindrop has indexed, used before a full reindex.
    func removeAll() async throws
    /// What Spotlight holds for Mindrop right now: each item's identifier and the line it
    /// draws. How the launch check finds items Spotlight lost.
    func indexedItems() async throws -> [String: String]
}

/// What only the app can add to an item: drawing an icon needs UIKit, and locating an
/// address needs MapKit. The share extension indexes without them; what it saves has no
/// category yet, and the app reindexes it once it has one.
public struct SpotlightExtras: Sendable {
    /// A PNG per category, shown on results in place of Mindrop's icon.
    public var categoryIcons: [MemoryCategory: Data]
    /// Coordinates for an address, for the Directions experiment. Nil when not found.
    public var locate: (@Sendable (String) async -> SpotlightLocation?)?

    public init(
        categoryIcons: [MemoryCategory: Data] = [:],
        locate: (@Sendable (String) async -> SpotlightLocation?)? = nil
    ) {
        self.categoryIcons = categoryIcons
        self.locate = locate
    }

    public static let none = SpotlightExtras()
}

public struct SpotlightLocation: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

#if canImport(CoreSpotlight)
// watchOS has no Spotlight: the watch app saves memories, the iPhone indexes them.

/// Core Spotlight implementation of the indexing boundary.
///
/// `@unchecked` because `CSSearchableIndex` is not annotated `Sendable`; Apple
/// documents it as safe to use from any thread, and the reference here is immutable.
public struct CoreSpotlightIndexer: SpotlightIndexing, @unchecked Sendable {
    private let searchableIndex: CSSearchableIndex
    private let extras: SpotlightExtras

    public init(searchableIndex: CSSearchableIndex = .default(), extras: SpotlightExtras = .none) {
        self.searchableIndex = searchableIndex
        self.extras = extras
    }

    public func index(_ items: [SpotlightAttributes]) async throws {
        guard !items.isEmpty else { return }
        var searchableItems: [CSSearchableItem] = []
        for attributes in items {
            var location: SpotlightLocation?
            if let address = attributes.address, let locate = extras.locate {
                location = await locate(address)
            }
            searchableItems.append(Self.searchableItem(
                for: attributes,
                icon: attributes.iconCategory.flatMap { extras.categoryIcons[$0] },
                location: location
            ))
        }
        try await searchableIndex.indexSearchableItems(searchableItems)
    }

    public func remove(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await searchableIndex.deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }

    public func removeAll() async throws {
        try await searchableIndex.deleteSearchableItems(withDomainIdentifiers: [SpotlightAttributes.domain])
    }

    public func indexedItems() async throws -> [String: String] {
        // The names `SearchableItemAttribute` gives these attributes from iOS 27 on,
        // spelled out because Mindrop still runs on iOS 26.
        let context = CSSearchQueryContext()
        context.fetchAttributes = ["kMDItemDisplayName"]
        let query = CSSearchQuery(
            queryString: "_kMDItemDomainIdentifier == \"\(SpotlightAttributes.domain)\"",
            queryContext: context
        )
        var found: [String: String] = [:]
        for try await result in query.results {
            found[result.item.uniqueIdentifier] = result.item.attributeSet.displayName ?? ""
        }
        return found
    }

    static func searchableItem(
        for attributes: SpotlightAttributes,
        icon: Data? = nil,
        location: SpotlightLocation? = nil
    ) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = attributes.title
        attributeSet.displayName = attributes.displayName
        attributeSet.textContent = attributes.textContent
        attributeSet.keywords = attributes.keywords
        // Ranking signals. Every memory is something the user wrote down themselves,
        // which Spotlight documents as telling it apart from content an app pushes.
        attributeSet.userCreated = true
        attributeSet.lastUsedDate = attributes.lastUsedDate
        attributeSet.rankingHint = attributes.rankingHint.map(NSNumber.init(value:))
        attributeSet.thumbnailData = icon
        // Spotlight draws a Call button for these, and a Directions button for the
        // coordinates. On the simulator both appeared only after it was restarted.
        if let phoneNumber = attributes.phoneNumber {
            attributeSet.phoneNumbers = [phoneNumber]
            attributeSet.supportsPhoneCall = true
        }
        if let location {
            attributeSet.latitude = NSNumber(value: location.latitude)
            attributeSet.longitude = NSNumber(value: location.longitude)
            attributeSet.supportsNavigation = true
        }

        let item = CSSearchableItem(
            uniqueIdentifier: attributes.identifier,
            domainIdentifier: attributes.domainIdentifier,
            attributeSet: attributeSet
        )
        // Indexed items otherwise expire about a month after indexing, which would
        // make saved memories quietly disappear from Spotlight.
        item.expirationDate = attributes.expirationDate
        return item
    }
}
#endif
