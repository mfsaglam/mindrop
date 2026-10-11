import Foundation

/// Picks the value for a memory out of what the share sheet handed over.
public enum SharedTextParser {
    /// Returns the first candidate that holds something after normalisation.
    public static func value(from candidates: [String?]) -> String? {
        for candidate in candidates {
            guard let candidate else { continue }
            let value = MemoryNormalizer.normalizeValue(candidate)
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Converts whatever `NSItemProvider` hands back into text.
    ///
    /// A shared link arrives as a URL rather than a string, and some hosts pass
    /// attributed text or raw UTF-8 data.
    public static func text(fromLoadedItem item: Any?) -> String? {
        switch item {
        case let string as String: string
        case let attributed as NSAttributedString: attributed.string
        case let url as URL: url.absoluteString
        case let data as Data: String(data: data, encoding: .utf8)
        default: nil
        }
    }
}
