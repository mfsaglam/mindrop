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
    /// The field Spotlight matches a query against: the value, then the keyword.
    public let title: String
    /// What Spotlight draws. Value only, when the system honours it.
    public let displayName: String
    /// The keyword as a whole plus its individual words. Not displayed.
    public let keywords: [String]
    /// The same words again, through a second metadata field. Not displayed.
    public let alternateNames: [String]
    public let domainIdentifier: String

    public static let domain = "memory"
}

public enum SpotlightAttributesFactory {
    /// Whether the keyword is appended to the title.
    ///
    /// On a physical iPhone (iOS 26), searching a memory's *value* finds it while
    /// searching its *keyword* does not, even with `keywords`, `alternateNames` and
    /// `contentDescription` all populated. The title is the one field that matches,
    /// so the keyword has to live there. Setting this to false gives a value-only
    /// title and gives up keyword search.
    public static let keywordInTitle = true

    /// Whether the displayed name stays value-only while the title carries the keyword.
    ///
    /// Spotlight draws `displayName` in preference to `title` but matches against the
    /// title, so this should leave a clean single line reading just the value. If a
    /// device test shows the keyword in the row anyway, nothing is lost. If keyword
    /// search stops working, set this to false: the row then reads
    /// `"SuperFast2026! · wifi"`, which is known to match.
    public static let displayValueOnly = true

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
