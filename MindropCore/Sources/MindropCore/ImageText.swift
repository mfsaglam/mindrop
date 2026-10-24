import Foundation

/// What was read from a shared image, as lines to pick the details from.
///
/// Reading happens elsewhere (Vision, on the device); this decides what is offered
/// and how picking a line changes the details.
public enum ImageText {
    /// QR codes first, as they are usually the point of the image, then the text
    /// lines in reading order. A Wi-Fi code becomes the network and password.
    /// Blank lines and repeats are dropped.
    public static func lines(recognized: [String], codes: [String]) -> [String] {
        var seen: Set<String> = []
        let codes = codes.map { WiFiCredentials(qrPayload: $0)?.memoryValue ?? $0 }
        return (codes + recognized)
            .map(MemoryNormalizer.normalizeValue)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Whether the details already hold this line, as one of their own lines.
    public static func details(_ details: String, contain line: String) -> Bool {
        position(of: detailLines(line), in: detailLines(details)) != nil
    }

    /// Adds the line on a new line of its own, or takes it out if it is already there,
    /// so several lines can be picked (an address over three lines) and a wrong pick
    /// undone, without losing anything typed around them.
    public static func toggling(_ line: String, in details: String) -> String {
        var held = detailLines(details)
        let picked = detailLines(line)
        if let range = position(of: picked, in: held) {
            held.removeSubrange(range)
        } else {
            held += picked
        }
        return held.joined(separator: "\n")
    }

    /// Where the picked lines sit, together and in order, among the held ones.
    private static func position(of picked: [String], in held: [String]) -> Range<Int>? {
        guard !picked.isEmpty, picked.count <= held.count else { return nil }
        return (0...(held.count - picked.count))
            .map { $0..<($0 + picked.count) }
            .first { Array(held[$0]) == picked }
    }

    private static func detailLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { MemoryNormalizer.normalizeValue(String($0)) }
            .filter { !$0.isEmpty }
    }
}
