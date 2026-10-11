import Foundation

/// The metadata Mindrop hands to Core Spotlight for one memory, as plain data.
///
/// Kept free of Core Spotlight types so the indexing strategy — the riskiest
/// assumption in the product — is unit-testable without a search index.
public struct SpotlightAttributes: Equatable, Sendable {
    /// Must be the memory's UUID: it is how a tapped Spotlight result is routed back.
    public let identifier: String
    /// Kept equal to `displayName`, for any surface that reads the title instead.
    public let title: String
    /// The line Spotlight draws, and the line it matches against.
    public let displayName: String
    /// Body text. Spotlight draws it as a smaller second line when it is set.
    public let textContent: String?
    /// The keyword as a whole plus its individual words. Never displayed, and on
    /// iOS 26 never matched either; kept in case a later release consults them.
    public let keywords: [String]
    /// The same words again, through a second metadata field.
    public let alternateNames: [String]
    public let domainIdentifier: String

    public static let domain = "memory"
}

/// Where the keyword is put so that Spotlight will match it.
///
/// Measured on a physical iPhone (iOS 26). `keywords`, `alternateNames` and
/// `contentDescription` never reach the matcher, and neither does `title` once
/// `displayName` overrides it, so Spotlight appears to match only what it draws.
/// Each case below therefore trades a visible keyword against keyword search.
public enum KeywordPlacement: Sendable {
    /// Appended to the drawn name: `"SuperFast2026! · wifi"`, one line.
    /// Confirmed working on device.
    case displayedName
    /// In `textContent`, which Spotlight draws as a smaller second line under the
    /// value: the big line stays `"SuperFast2026!"` and `"wifi"` sits beneath it.
    /// Under test — if the keyword stops being findable, this field is not matched
    /// either and `.displayedName` is the answer.
    case bodyText
    /// Nowhere visible. The row is just the value, and keyword search does not work.
    case hidden
}

public enum SpotlightAttributesFactory {
    public static let keywordPlacement: KeywordPlacement = .bodyText

    public static func make(for memory: Memory) -> SpotlightAttributes {
        let words = searchKeywords(for: memory.keyword)
        let name = displayName(for: memory)
        return SpotlightAttributes(
            identifier: memory.id.uuidString,
            title: name,
            displayName: name,
            textContent: textContent(for: memory),
            keywords: words,
            alternateNames: words,
            domainIdentifier: SpotlightAttributes.domain
        )
    }

    /// The value always leads, so it stays the prominent text whatever else is shown.
    static func displayName(for memory: Memory) -> String {
        switch keywordPlacement {
        case .displayedName: "\(memory.value) · \(memory.keyword)"
        case .bodyText, .hidden: memory.value
        }
    }

    /// The keyword alone: repeating the value here would draw it twice.
    static func textContent(for memory: Memory) -> String? {
        switch keywordPlacement {
        case .bodyText: memory.keyword
        case .displayedName, .hidden: nil
        }
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
