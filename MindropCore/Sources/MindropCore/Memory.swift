import Foundation

/// A single keyword → value pair, optionally filed under a category.
public struct Memory: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var keyword: String
    public var value: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Optional, so files written before categories existed still decode.
    public var category: CategoryAssignment?
    /// When a temporary memory expires: it leaves Spotlight then, and is deleted for good
    /// `MemoryLifetime.expiredRetention` later. Nil for a memory kept forever.
    public var expiresAt: Date?
    /// Kept out of Spotlight and hidden in the app until the user unlocks it. Off unless
    /// the user turns it on.
    public var isSensitive: Bool
    /// When the memory last changed in any way, its text or anything about it. What iCloud
    /// sync compares: the later change wins. `updatedAt` is the text edit alone.
    public var modifiedAt: Date
    /// When the memory was moved to Recently Deleted. Nil while it is not deleted.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        keyword: String,
        value: String,
        createdAt: Date,
        updatedAt: Date,
        category: CategoryAssignment? = nil,
        expiresAt: Date? = nil,
        isSensitive: Bool = false,
        modifiedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.keyword = keyword
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.category = category
        self.expiresAt = expiresAt
        self.isSensitive = isSensitive
        self.modifiedAt = modifiedAt ?? updatedAt
        self.deletedAt = deletedAt
    }

    /// Written out by hand only so that files saved before a field existed still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyword = try container.decode(String.self, forKey: .keyword)
        value = try container.decode(String.self, forKey: .value)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        category = try container.decodeIfPresent(CategoryAssignment.self, forKey: .category)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? updatedAt
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

public enum MemoryValidationError: Error, Equatable, Sendable {
    case emptyKeyword
    case keywordTooShort
    case emptyValue
}

/// Normalisation rules, kept in one place so the app and the share extension agree.
///
/// The keyword is a lookup token, so interior whitespace is collapsed. The value is
/// user content: only the outer edges are trimmed, everything inside is preserved
/// exactly as typed (line breaks, spacing in an IBAN, punctuation in a password).
public enum MemoryNormalizer {
    public static let minimumKeywordLength = 4

    public static func normalizeKeyword(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func normalizeValue(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates the saved text, including the minimum keyword length needed for Spotlight.
    public static func validate(keyword: String, value: String) throws -> (keyword: String, value: String) {
        let keyword = normalizeKeyword(keyword)
        guard !keyword.isEmpty else { throw MemoryValidationError.emptyKeyword }
        guard keyword.count >= minimumKeywordLength else { throw MemoryValidationError.keywordTooShort }
        let value = normalizeValue(value)
        guard !value.isEmpty else { throw MemoryValidationError.emptyValue }
        return (keyword, value)
    }
}

public extension Memory {
    /// Creates a validated memory. `now` is injected so tests and callers control timestamps.
    static func make(
        keyword: String,
        value: String,
        now: Date,
        expiresAt: Date? = nil,
        isSensitive: Bool = false,
        id: UUID = UUID()
    ) throws -> Memory {
        let fields = try MemoryNormalizer.validate(keyword: keyword, value: value)
        return Memory(
            id: id,
            keyword: fields.keyword,
            value: fields.value,
            createdAt: now,
            updatedAt: now,
            expiresAt: expiresAt,
            isSensitive: isSensitive
        )
    }

    /// Returns a copy with validated new fields, or the receiver unchanged if nothing differs.
    ///
    /// An automatic category is dropped, since it described the old text; the memory is
    /// then categorised again. A category the user picked is kept. Changing only the
    /// expiry or whether it is sensitive is not a new edit: the memory keeps its place in
    /// the list.
    func updating(keyword: String, value: String, expiresAt: Date?, isSensitive: Bool, now: Date) throws -> Memory {
        let fields = try MemoryNormalizer.validate(keyword: keyword, value: value)
        var copy = self
        copy.expiresAt = expiresAt
        copy.isSensitive = isSensitive
        if fields.keyword != self.keyword || fields.value != self.value {
            copy.keyword = fields.keyword
            copy.value = fields.value
            copy.updatedAt = now
            if copy.category?.source == .automatic { copy.category = nil }
        }
        if copy != self { copy.modifiedAt = now }
        return copy
    }

    /// An edit of the text only, keeping whatever expiry and sensitivity the memory has.
    func updating(keyword: String, value: String, now: Date) throws -> Memory {
        try updating(keyword: keyword, value: value, expiresAt: expiresAt, isSensitive: isSensitive, now: now)
    }

    /// Past its expiry: out of Spotlight, and listed under Expired until it is deleted.
    func isExpired(at now: Date) -> Bool {
        expiresAt.map { $0 <= now } ?? false
    }

    /// When an expired memory is deleted for good. Nil for a memory kept forever.
    var deletionDate: Date? {
        expiresAt?.addingTimeInterval(MemoryLifetime.expiredRetention)
    }

    /// How long a deleted memory stays in Recently Deleted before it is deleted for good.
    static let deletedRetention: TimeInterval = 30 * 24 * 60 * 60

    /// In Recently Deleted: out of Spotlight and out of the list, but recoverable.
    var isDeleted: Bool { deletedAt != nil }

    /// When a memory in Recently Deleted is deleted for good.
    var deletedForGoodDate: Date? {
        deletedAt?.addingTimeInterval(Self.deletedRetention)
    }

    /// Past every retention: an expired memory 7 days on, a deleted one 30 days on.
    func isDueForDeletion(at now: Date) -> Bool {
        if let deletedForGoodDate, deletedForGoodDate <= now { return true }
        if !isDeleted, let deletionDate, deletionDate <= now { return true }
        return false
    }

    /// Two versions of the same memory, one from this device and one from iCloud, as one.
    ///
    /// The later change wins as a whole, with one exception: the text is never lost to a
    /// later change of something else. If the other version's text is newer, it is kept,
    /// along with its category unless the winner's category was picked by the user. So
    /// one iPhone filing a memory while another edits it keeps the edit.
    static func merged(local: Memory, remote: Memory) -> Memory {
        let remoteWins = remote.modifiedAt > local.modifiedAt
        var winner = remoteWins ? remote : local
        let other = remoteWins ? local : remote
        if other.updatedAt > winner.updatedAt {
            winner.keyword = other.keyword
            winner.value = other.value
            winner.updatedAt = other.updatedAt
            if winner.category?.source != .manual { winner.category = other.category }
        }
        winner.createdAt = min(local.createdAt, remote.createdAt)
        return winner
    }

    /// Whether the categorizer should look at this memory: it has no category, or an
    /// automatic one from an older categorizer. A manual choice is final.
    func needsCategory(categorizerVersion: Int) -> Bool {
        guard let category else { return true }
        return category.source == .automatic && category.version != categorizerVersion
    }

    /// In-app filtering. Every word of the query must be found in the keyword or the
    /// value, in any order, case- and diacritic-insensitively: "ev wifi" finds
    /// "ev wifi şifresi", and so does "wifi ev", much as Spotlight would. That matters for
    /// a search carried on from Spotlight. A sensitive memory matches on its keyword only,
    /// so typing part of a hidden value does not reveal which memory holds it.
    func matches(query: String) -> Bool {
        SearchHighlight.terms(in: query).allSatisfy { term in
            SearchHighlight.contains(term, in: keyword) || (!isSensitive && SearchHighlight.contains(term, in: value))
        }
    }
}

/// Where a search's words appear in a text, for highlighting them in results.
public enum SearchHighlight {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The query's words, without repeats.
    public static func terms(in query: String) -> [String] {
        var seen: Set<String> = []
        return query.split(whereSeparator: \.isWhitespace).map(String.init).filter { seen.insert($0.lowercased()).inserted }
    }

    static func contains(_ term: String, in text: String) -> Bool {
        text.range(of: term, options: options) != nil
    }

    /// Every place any of the query's words appears in `text`, in order, overlaps merged.
    public static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for term in terms(in: query) {
            var start = text.startIndex
            while start < text.endIndex, let range = text.range(of: term, options: options, range: start..<text.endIndex) {
                found.append(range)
                start = range.upperBound
            }
        }
        var merged: [Range<String.Index>] = []
        for range in found.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
