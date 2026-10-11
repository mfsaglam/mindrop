import Foundation

/// The metadata Mindrop hands to Core Spotlight for one memory, as plain data.
///
/// Kept free of Core Spotlight types so the indexing strategy — the riskiest
/// assumption in the product — is unit-testable without a search index.
public struct SpotlightAttributes: Equatable, Sendable {
    /// Must be the memory's UUID: it is how a tapped Spotlight result is routed back.
    public let identifier: String
    /// The value. Spotlight renders this as the result's primary line.
    public let title: String
    /// The keyword. Shown as the smaller secondary line, and searched by Spotlight,
    /// which makes keyword matching far more dependable than `keywords` alone.
    public let contentDescription: String
    /// The keyword as a whole plus its individual words, for match coverage.
    public let keywords: [String]
    public let domainIdentifier: String

    public static let domain = "memory"
}

public enum SpotlightAttributesFactory {
    public static func make(for memory: Memory) -> SpotlightAttributes {
        SpotlightAttributes(
            identifier: memory.id.uuidString,
            title: memory.value,
            contentDescription: memory.keyword,
            keywords: searchKeywords(for: memory.keyword),
            domainIdentifier: SpotlightAttributes.domain
        )
    }

    /// `"office door"` → `["office door", "office", "door"]`.
    ///
    /// Spotlight matches a query against whole keywords, so a multi-word keyword is
    /// also split: typing just `door` should still find it. Duplicates are dropped
    /// case-insensitively; matching itself is case-insensitive.
    static func searchKeywords(for keyword: String) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for candidate in [keyword] + keyword.split(whereSeparator: \.isWhitespace).map(String.init) {
            let key = candidate.lowercased()
            guard !candidate.isEmpty, seen.insert(key).inserted else { continue }
            result.append(candidate)
        }
        return result
    }
}
