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

    public init(
        id: UUID = UUID(),
        keyword: String,
        value: String,
        createdAt: Date,
        updatedAt: Date,
        category: CategoryAssignment? = nil,
        expiresAt: Date? = nil,
        isSensitive: Bool = false
    ) {
        self.id = id
        self.keyword = keyword
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.category = category
        self.expiresAt = expiresAt
        self.isSensitive = isSensitive
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
    }
}

public enum MemoryValidationError: Error, Equatable, Sendable {
    case emptyKeyword
    case emptyValue
}

/// Normalisation rules, kept in one place so the app and the share extension agree.
///
/// The keyword is a lookup token, so interior whitespace is collapsed. The value is
/// user content: only the outer edges are trimmed, everything inside is preserved
/// exactly as typed (line breaks, spacing in an IBAN, punctuation in a password).
public enum MemoryNormalizer {
    public static func normalizeKeyword(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func normalizeValue(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates and normalises a keyword/value pair, or throws if either side is empty.
    public static func validate(keyword: String, value: String) throws -> (keyword: String, value: String) {
        let keyword = normalizeKeyword(keyword)
        guard !keyword.isEmpty else { throw MemoryValidationError.emptyKeyword }
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

    /// Whether the categorizer should look at this memory: it has no category, or an
    /// automatic one from an older categorizer. A manual choice is final.
    func needsCategory(categorizerVersion: Int) -> Bool {
        guard let category else { return true }
        return category.source == .automatic && category.version != categorizerVersion
    }

    /// In-app filtering. Matches on keyword and value, case- and diacritic-insensitively.
    /// A sensitive memory matches on its keyword only, so typing part of a hidden value
    /// does not reveal which memory holds it.
    func matches(query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return keyword.range(of: query, options: options) != nil
            || (!isSensitive && value.range(of: query, options: options) != nil)
    }
}
