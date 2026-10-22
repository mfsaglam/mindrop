import Foundation
import MindropCore
import SwiftUI

/// The one thing a value lets you do besides copy and share it, when there is one: open a
/// web address, get directions to a place, or call a number. Offered beside Copy on the
/// detail screen.
struct MemoryAction {
    enum Kind {
        case open
        case directions
        case call
    }

    let kind: Kind
    let url: URL

    /// Numbers are only trusted where a phone number is what the memory is about, because
    /// the system's detector also reads card and social security numbers as phone numbers.
    /// Wider than Spotlight's Call button: Health holds doctors and pharmacies.
    static let callableCategories: Set<MemoryCategory> = ValueDetector.callableCategories.union([.health])

    init?(memory: Memory) {
        let value = memory.value
        if let url = Self.webAddress(in: value) {
            (kind, self.url) = (.open, url)
        } else if let address = ValueDetector.address(in: value, category: memory.category?.category),
                  let url = Self.directions(to: address) {
            (kind, self.url) = (.directions, url)
        } else if let number = ValueDetector.phoneNumber(
                      in: value,
                      category: memory.category?.category,
                      categories: Self.callableCategories
                  ),
                  let url = URL(string: "tel:\(number.filter { $0.isNumber || $0 == "+" })") {
            (kind, self.url) = (.call, url)
        } else {
            return nil
        }
    }

    var title: LocalizedStringResource {
        switch kind {
        case .open: "Open"
        case .directions: "Directions"
        case .call: "Call"
        }
    }

    var symbolName: String {
        switch kind {
        case .open: "safari"
        case .directions: "arrow.triangle.turn.up.right.diamond.fill"
        case .call: "phone.fill"
        }
    }

    /// A value that is a web address and nothing else; "example.com/menu" counts.
    private static func webAddress(in value: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.range == NSRange(value.startIndex..., in: value),
              let url = match.url,
              ["http", "https"].contains(url.scheme?.lowercased())
        else { return nil }
        return url
    }

    /// Apple Maps, routing to the address from where the user is.
    private static func directions(to address: String) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "daddr", value: address)]
        return components?.url
    }
}
