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
}
