import Foundation

/// Finds the parts of a value Spotlight can act on: a number to call, a place to go to.
enum ValueDetector {
    /// Categories whose numbers are worth a Call button. The system's detector also reads
    /// a social security number, "987-65-4321", as a phone number, so it is only trusted
    /// where a phone number is what the memory is about.
    static let callableCategories: Set<MemoryCategory> = [.contact, .people]

    /// The first phone number in a memory filed under Contacts or Family & People, as
    /// written.
    static func phoneNumber(in value: String, category: MemoryCategory?) -> String? {
        guard let category, callableCategories.contains(category) else { return nil }
        return firstMatch(of: .phoneNumber, in: value)?.phoneNumber
    }

    /// The value itself for a memory filed under Places, otherwise the first address the
    /// system recognises in it. Recognition is weak outside a few countries' formats, so
    /// the category counts for more.
    static func address(in value: String, category: MemoryCategory?) -> String? {
        if category == .address { return value }
        guard let match = firstMatch(of: .address, in: value),
              let range = Range(match.range, in: value)
        else { return nil }
        return String(value[range])
    }

    private static func firstMatch(of type: NSTextCheckingResult.CheckingType, in value: String) -> NSTextCheckingResult? {
        guard let detector = try? NSDataDetector(types: type.rawValue) else { return nil }
        return detector.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
    }
}
