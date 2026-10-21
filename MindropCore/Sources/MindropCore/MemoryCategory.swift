import Foundation

/// A fixed set of kinds of thing people keep in Mindrop.
///
/// Fixed rather than free-form on purpose: a model inventing names produces "Wi-Fi",
/// "WiFi Password" and "Network" for the same thing, which makes a filter useless and
/// cannot be translated. The raw values are persisted, so never rename one. Declaration
/// order is the order menus show.
public enum MemoryCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case network
    case account
    case code
    case finance
    case contact
    case people
    case address
    case home
    case vehicle
    case document
    case health
    case link
    case other

    /// A category that follows from the value alone, with no model needed. The model
    /// filed a bare link under other and a card number under document; a rule cannot.
    public static func evident(fromValue value: String) -> MemoryCategory? {
        if isWebLink(value) { return .link }
        if startsWithCardNumber(value) { return .finance }
        return nil
    }

    private static func isWebLink(_ value: String) -> Bool {
        guard !value.contains(where: \.isWhitespace),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return false }
        return url.host() != nil
    }

    /// 13 to 19 digits at the start, in groups split by spaces or dashes, passing the
    /// Luhn check — so "4111 1111 1111 1111 12/28 123" counts, and an 11-digit national
    /// ID or a 9-digit social security number does not.
    private static func startsWithCardNumber(_ value: String) -> Bool {
        var digits: [Int] = []
        for group in value.split(whereSeparator: { $0 == " " || $0 == "-" }) {
            guard group.allSatisfy(\.isASCII), group.allSatisfy(\.isNumber) else { break }
            digits += group.compactMap(\.wholeNumberValue)
            if digits.count >= 13 { break }
        }
        guard (13...19).contains(digits.count) else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { sum, pair in
            guard pair.offset.isMultiple(of: 2) == false else { return sum + pair.element }
            let doubled = pair.element * 2
            return sum + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum.isMultiple(of: 10)
    }
}

/// Which category a memory is in, and who decided.
public struct CategoryAssignment: Codable, Sendable, Hashable {
    public enum Source: String, Codable, Sendable {
        /// Suggested by the on-device model. Cleared when the memory is edited.
        case automatic
        /// Picked by the user. Never overwritten.
        case manual
    }

    public var category: MemoryCategory
    public var source: Source
    /// The categorizer version that made an automatic choice. When the categorizer
    /// improves, automatic choices from older versions are redone. Nil for manual
    /// choices, and for automatic ones made before versions existed.
    public var version: Int?

    public init(category: MemoryCategory, source: Source, version: Int? = nil) {
        self.category = category
        self.source = source
        self.version = version
    }
}

/// Suggests a category for a keyword/value pair. Returns nil when it cannot or will not
/// decide — no model on this device, an unsupported language, a refusal — in which case
/// the memory stays uncategorised.
public protocol MemoryCategorizing: Sendable {
    /// Bump whenever the categories, prompt or rules change, so earlier automatic
    /// choices are made again.
    var version: Int { get }
    /// Takes the whole memory, not just its text, so an implementation can attribute
    /// what it does to a memory — the app's debug log counts requests per memory.
    func category(for memory: Memory) async -> MemoryCategory?
}

/// One section of the list grouped by category.
public struct CategorySection: Identifiable, Equatable, Sendable {
    /// Nil for the memories without a category yet.
    public let category: MemoryCategory?
    public let memories: [Memory]

    public var id: String { category?.rawValue ?? "uncategorised" }
}

public extension Array where Element == Memory {
    /// Sections in the categories' declaration order, uncategorised last, empty ones
    /// left out. Each section keeps the order it was given, so newest first stays.
    func groupedByCategory() -> [CategorySection] {
        let groups = Dictionary(grouping: self) { $0.category?.category }
        let ordered: [MemoryCategory?] = MemoryCategory.allCases.map(Optional.some) + [nil]
        return ordered.compactMap { category in
            guard let memories = groups[category], !memories.isEmpty else { return nil }
            return CategorySection(category: category, memories: memories)
        }
    }
}
