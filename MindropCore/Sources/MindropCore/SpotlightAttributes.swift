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
    /// iOS 26 and 27 never matched either; kept in case a later release consults them.
    ///
    /// Not `alternateNames` as well: iOS 27 draws its first entry as a grey second line,
    /// which only repeated the keyword. Without it, a long value wraps onto two lines
    /// and keeps the keyword in view.
    public let keywords: [String]
    public let domainIdentifier: String
    /// When Spotlight drops the item by itself: a temporary memory's expiry, so it
    /// disappears on time even if the app is not opened. Never for a memory kept forever.
    public let expirationDate: Date
    /// When the memory was last opened or copied on this device. A ranking signal.
    public let lastUsedDate: Date?
    /// How much the memory is used, relative to the others: 0 to 100. A ranking signal.
    public let rankingHint: Int?
    /// Whose icon the result shows instead of Mindrop's.
    public let iconCategory: MemoryCategory?
    /// For Spotlight's Call button. Never for a sensitive memory.
    public let phoneNumber: String?
    /// For Spotlight's Directions button, once located. Never for a sensitive memory.
    public let address: String?

    public static let domain = "memory"

    /// The memory this item was made from.
    public var memoryID: UUID? { UUID(uuidString: identifier) }
}

/// Where the keyword is put so that Spotlight will match it.
///
/// Measured on a physical iPhone (iOS 26) over four rounds: `keywords`,
/// `alternateNames`, `contentDescription`, `textContent` and `title` are all ignored
/// by the matcher. `displayName` is the only field a Spotlight query matches against.
/// Measured again on iOS 27, on the simulator and on a physical iPhone, with `.bodyText`:
/// still true. So the placement is fixed in code, not an experiment any more.
///
/// So the keyword is findable only when it is part of the drawn name, and each case
/// below is really a choice between a visible keyword and keyword search at all.
public enum KeywordPlacement: String, Codable, Sendable, CaseIterable {
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

    public static func make(
        for memory: Memory,
        options: SpotlightOptions = .shipping,
        usage: SpotlightUsage? = nil
    ) -> SpotlightAttributes {
        make(for: memory, options: options, usage: usage, placement: keywordPlacement)
    }

    /// With a placement other than the shipped one, for tests.
    static func make(
        for memory: Memory,
        options: SpotlightOptions = .shipping,
        usage: SpotlightUsage? = nil,
        placement: KeywordPlacement
    ) -> SpotlightAttributes {
        let words = searchKeywords(for: memory.keyword)
        let name = displayName(for: memory, placement: placement)
        let category = memory.category?.category
        // A sensitive memory's value never reaches Spotlight, not even as a phone number.
        let actsOnValue = !memory.isSensitive
        return SpotlightAttributes(
            identifier: memory.id.uuidString,
            title: name,
            displayName: name,
            textContent: textContent(for: memory, placement: placement),
            keywords: words,
            domainIdentifier: SpotlightAttributes.domain,
            expirationDate: memory.expiresAt ?? .distantFuture,
            lastUsedDate: usage?.lastUsedAt,
            rankingHint: usage?.rankingHint,
            iconCategory: options.showsCategoryIcon ? category : nil,
            phoneNumber: options.offersCall && actsOnValue ? ValueDetector.phoneNumber(in: memory.value, category: category) : nil,
            address: options.offersDirections && actsOnValue ? ValueDetector.address(in: memory.value, category: category) : nil
        )
    }

    /// The value always leads, so it stays the prominent text whatever else is shown.
    /// A sensitive memory never hands its value to Spotlight: the keyword and a lock
    /// stand in, so it is still found, and tapping it opens Mindrop, which asks to unlock.
    static func displayName(for memory: Memory, placement: KeywordPlacement) -> String {
        if memory.isSensitive { return "\(memory.keyword) · \(sensitivePlaceholder)" }
        return switch placement {
        case .displayedName: "\(memory.value) · \(memory.keyword)"
        case .bodyText, .hidden: memory.value
        }
    }

    static let sensitivePlaceholder = "🔒"

    /// The keyword alone: repeating the value here would draw it twice.
    static func textContent(for memory: Memory, placement: KeywordPlacement) -> String? {
        switch placement {
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
