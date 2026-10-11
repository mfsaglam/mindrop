import Foundation

/// A single keyword → value pair. This is the entire data model of Mindrop.
public struct Memory: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var keyword: String
    public var value: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), keyword: String, value: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.keyword = keyword
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
    static func make(keyword: String, value: String, now: Date, id: UUID = UUID()) throws -> Memory {
        let fields = try MemoryNormalizer.validate(keyword: keyword, value: value)
        return Memory(id: id, keyword: fields.keyword, value: fields.value, createdAt: now, updatedAt: now)
    }

    /// Returns a copy with validated new fields, or the receiver unchanged if nothing differs.
    func updating(keyword: String, value: String, now: Date) throws -> Memory {
        let fields = try MemoryNormalizer.validate(keyword: keyword, value: value)
        guard fields.keyword != self.keyword || fields.value != self.value else { return self }
        var copy = self
        copy.keyword = fields.keyword
        copy.value = fields.value
        copy.updatedAt = now
        return copy
    }

    /// In-app filtering. Matches on keyword and value, case- and diacritic-insensitively.
    func matches(query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return keyword.range(of: query, options: options) != nil
            || value.range(of: query, options: options) != nil
    }
}
