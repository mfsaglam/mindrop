import MindropCore
import SwiftUI

/// User content with a search's words marked, the way Notes marks what was searched for.
/// Plain text when there is no search. Shown verbatim either way, never looked up.
struct HighlightedText: View {
    let text: String
    let query: String?

    init(_ text: String, query: String?) {
        self.text = text
        self.query = query
    }

    var body: some View {
        Text(Self.attributed(text, query: query))
    }

    static func attributed(_ text: String, query: String?) -> AttributedString {
        var result = AttributedString(text)
        guard let query else { return result }
        for range in SearchHighlight.ranges(of: query, in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result)
            else { continue }
            // Bold keeps whatever size and design the surrounding text has.
            result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            result[lower..<upper].backgroundColor = .yellow.opacity(0.35)
        }
        return result
    }
}
