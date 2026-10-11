import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Indexing boundary, so synchronisation logic can be tested against a spy.
public protocol SpotlightIndexing: Sendable {
    func index(_ memories: [Memory]) async throws
    func remove(ids: [UUID]) async throws
    /// Removes every memory Mindrop has indexed, used before a full reindex.
    func removeAll() async throws
}

/// Core Spotlight implementation of the indexing boundary.
///
/// `@unchecked` because `CSSearchableIndex` is not annotated `Sendable`; Apple
/// documents it as safe to use from any thread, and the reference here is immutable.
public struct CoreSpotlightIndexer: SpotlightIndexing, @unchecked Sendable {
    private let searchableIndex: CSSearchableIndex

    public init(searchableIndex: CSSearchableIndex = .default()) {
        self.searchableIndex = searchableIndex
    }

    public func index(_ memories: [Memory]) async throws {
        guard !memories.isEmpty else { return }
        try await searchableIndex.indexSearchableItems(memories.map(Self.searchableItem))
    }

    public func remove(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await searchableIndex.deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }

    public func removeAll() async throws {
        try await searchableIndex.deleteSearchableItems(withDomainIdentifiers: [SpotlightAttributes.domain])
    }

    static func searchableItem(for memory: Memory) -> CSSearchableItem {
        let attributes = SpotlightAttributesFactory.make(for: memory)
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = attributes.title
        attributeSet.contentDescription = attributes.contentDescription
        attributeSet.keywords = attributes.keywords
        attributeSet.displayName = attributes.title

        let item = CSSearchableItem(
            uniqueIdentifier: attributes.identifier,
            domainIdentifier: attributes.domainIdentifier,
            attributeSet: attributeSet
        )
        // Indexed items otherwise expire about a month after indexing, which would
        // make saved memories quietly disappear from Spotlight.
        item.expirationDate = .distantFuture
        return item
    }
}
