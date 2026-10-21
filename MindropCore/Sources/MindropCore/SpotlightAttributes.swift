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
    /// When Spotlight drops the item by itself: a temporary memory's expiry, so it
    /// disappears on time even if the app is not opened. Never for a memory kept forever.
    public let expirationDate: Date

    public static let domain = "memory"
}

/// Where the keyword is put so that Spotlight will match it.
///
/// Measured on a physical iPhone (iOS 26) over four rounds: `keywords`,
/// `alternateNames`, `contentDescription`, `textContent` and `title` are all ignored
/// by the matcher. `displayName` is the only field a Spotlight query matches against.
///
/// So the keyword is findable only when it is part of the drawn name, and each case
/// below is really a choice between a visible keyword and keyword search at all.
public enum KeywordPlacement: Sendable {
    /// Appended to the drawn name: `"SuperFast2026! · wifi"`, one line.
    /// Confirmed working on device.
    case displayedName
    /// In `textContent`, drawn as a smaller second line under the value.
    /// Tested on device: the row looks better and the keyword is not findable,
    /// because `textContent` is not matched. Kept for retesting on a later iOS.
    case bodyText
    /// Nowhere visible. The row is just the value, and keyword search does not work.
    case hidden
}

public enum SpotlightAttributesFactory {
    public static let keywordPlacement: KeywordPlacement = .displayedName

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
            domainIdentifier: SpotlightAttributes.domain,
            expirationDate: memory.expiresAt ?? .distantFuture
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
