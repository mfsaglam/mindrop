import Foundation

/// The metadata Mindrop hands to Core Spotlight for one memory, as plain data.
///
/// Kept free of Core Spotlight types so the indexing strategy — the riskiest
/// assumption in the product — is unit-testable without a search index.
public struct SpotlightAttributes: Equatable, Sendable {
    /// Must be the memory's UUID: it is how a tapped Spotlight result is routed back.
    public let identifier: String
    /// Spotlight renders this as the result's primary line, and it is the field the
    /// system reliably matches a query against. Value first, keyword after it.
    public let title: String
    /// What Spotlight displays as the primary line. Kept identical to `title`.
    public let displayName: String
    /// The keyword, shown as the smaller second line.
    public let contentDescription: String
    /// The keyword as a whole plus its individual words.
    public let keywords: [String]
    /// Extra names to match on, which Spotlight does not display.
    public let alternateNames: [String]
    /// Body text for full-text matching, which Spotlight does not display.
    public let textContent: String
    public let domainIdentifier: String

    public static let domain = "memory"
}

public enum SpotlightAttributesFactory {
    /// Whether the keyword is appended to the title.
    ///
    /// On a physical iPhone (iOS 26), searching a memory's *value* finds it, while
    /// searching its *keyword* does not — so neither `keywords` nor
    /// `contentDescription` is reaching the matcher, and the title is. Appending the
    /// keyword there is what makes `wifi` find `SuperFast2026!`.
    ///
    /// The value still leads the line, so it stays the prominent text. Set this to
    /// false to go back to a value-only title and retest metadata-only matching.
    public static let keywordInTitle = true

    public static func make(for memory: Memory) -> SpotlightAttributes {
        let title = title(for: memory)
        return SpotlightAttributes(
            identifier: memory.id.uuidString,
            title: title,
            displayName: title,
            contentDescription: memory.keyword,
            keywords: searchKeywords(for: memory.keyword),
            alternateNames: searchKeywords(for: memory.keyword),
            // Both fields, so a query matches whichever one the system consults.
            textContent: "\(memory.keyword)\n\(memory.value)",
            domainIdentifier: SpotlightAttributes.domain
        )
    }

    static func title(for memory: Memory) -> String {
        guard keywordInTitle else { return memory.value }
        return "\(memory.value) — \(memory.keyword)"
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
