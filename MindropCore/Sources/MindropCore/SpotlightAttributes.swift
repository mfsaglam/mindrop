import Foundation

/// The metadata Mindrop hands to Core Spotlight for one memory, as plain data.
///
/// Kept free of Core Spotlight types so the indexing strategy — the riskiest
/// assumption in the product — is unit-testable without a search index.
///
/// Deliberately absent: `contentDescription` and `textContent`. Both were set while
/// hunting for a field Spotlight would match the keyword against; both turned out to
/// be drawn in the result row, which put the keyword on screen twice more under the
/// title. Only the title matches, so only the title carries the keyword.
public struct SpotlightAttributes: Equatable, Sendable {
    /// Must be the memory's UUID: it is how a tapped Spotlight result is routed back.
    public let identifier: String
    /// The value, then the keyword.
    public let title: String
    /// What Spotlight both draws and matches against, so it carries the keyword too.
    public let displayName: String
    /// The keyword as a whole plus its individual words. Not displayed.
    public let keywords: [String]
    /// The same words again, through a second metadata field. Not displayed.
    public let alternateNames: [String]
    public let domainIdentifier: String

    public static let domain = "memory"
}

/// What three rounds of testing on a physical iPhone (iOS 26) established:
///
/// 1. Keyword in `keywords` + `contentDescription`, value as the title and display
///    name: the value finds the memory, the keyword does not.
/// 2. Keyword appended to both the title and the display name: the keyword finds it.
///    The row then showed the keyword three times, because Spotlight also draws
///    `contentDescription` and `textContent`.
/// 3. Those two dropped and the display name set back to the value alone, keyword
///    still in the title: the keyword stops finding it again.
///
/// So `keywords`, `alternateNames` and `contentDescription` do not reach the matcher,
/// and `title` on its own does not either — what Spotlight *draws* is what it matches.
/// The keyword has to be visible in the row for keyword search to work at all.
public enum SpotlightAttributesFactory {
    /// Whether the keyword is appended to the title. False gives up keyword search.
    public static let keywordInTitle = true

    /// Whether the displayed name is the value alone.
    ///
    /// Round 3 above: true looks cleaner and breaks keyword search, so it stays false.
    /// The display name is the title, and the row reads `"SuperFast2026! · wifi"`.
    public static let displayValueOnly = false

    public static func make(for memory: Memory) -> SpotlightAttributes {
        let words = searchKeywords(for: memory.keyword)
        return SpotlightAttributes(
            identifier: memory.id.uuidString,
            title: title(for: memory),
            displayName: displayName(for: memory),
            keywords: words,
            alternateNames: words,
            domainIdentifier: SpotlightAttributes.domain
        )
    }

    /// The matched line. The value leads it, so the value stays the prominent text
    /// even where Spotlight draws the title.
    static func title(for memory: Memory) -> String {
        guard keywordInTitle else { return memory.value }
        return "\(memory.value) · \(memory.keyword)"
    }

    static func displayName(for memory: Memory) -> String {
        displayValueOnly ? memory.value : title(for: memory)
    }

    /// `"office door"` → `["office door", "office", "door"]`.
    ///
    /// A multi-word keyword is also split, so typing just `door` can find it.
    /// Duplicates are dropped case-insensitively; matching itself is case-insensitive.
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
