import Foundation

/// How a value is best shown when there is room to show all of it, as in the preview
/// Spotlight opens on a long press.
///
/// Recognised only when the whole value is one thing: a card number followed by an expiry
/// date is shown as typed, because regrouping it would hide the user's own layout.
public enum ValueLayout: Equatable, Sendable {
    /// As typed.
    case text
    /// A card number or IBAN in blocks of four, for reading out or typing elsewhere.
    case groups([String])
    /// A recovery phrase, one word per numbered cell.
    case words([String])

    public init(value: String) {
        if let groups = Self.cardNumberGroups(value) ?? Self.ibanGroups(value) {
            self = .groups(groups)
        } else if let words = Self.recoveryPhrase(value) {
            self = .words(words)
        } else {
            self = .text
        }
    }

    /// 13 to 19 digits, spaces and dashes ignored, passing the Luhn check.
    static func cardNumberGroups(_ value: String) -> [String]? {
        let compact = value.filter { $0 != " " && $0 != "-" }
        guard (13...19).contains(compact.count), compact.allSatisfy({ $0.isASCII && $0.isNumber }),
              MemoryCategory.passesLuhn(compact.compactMap(\.wholeNumberValue))
        else { return nil }
        return chunks(of: compact)
    }

    /// Two letters, two check digits and up to 30 letters or digits, passing the mod-97
    /// check, so an ordinary code that happens to start with two letters is left alone.
    static func ibanGroups(_ value: String) -> [String]? {
        let compact = value.filter { $0 != " " }.uppercased()
        let characters = Array(compact)
        guard (15...34).contains(characters.count),
              characters.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              characters[0].isLetter, characters[1].isLetter,
              characters[2].isNumber, characters[3].isNumber
        else { return nil }

        // Move the first four characters to the end, letters become 10...35, and the
        // whole number must leave 1 when divided by 97. Done digit by digit, since the
        // number has up to 70 digits.
        var remainder = 0
        for character in characters[4...] + characters[..<4] {
            let digits = character.isNumber ? String(character) : String(Int(character.asciiValue! - 55))
            for digit in digits {
                remainder = (remainder * 10 + digit.wholeNumberValue!) % 97
            }
        }
        return remainder == 1 ? chunks(of: compact) : nil
    }

    /// 12, 15, 18, 21 or 24 lowercase words of letters only: the shape of a wallet's
    /// recovery phrase.
    static func recoveryPhrase(_ value: String) -> [String]? {
        let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
        guard [12, 15, 18, 21, 24].contains(words.count),
              words.allSatisfy({ word in word.allSatisfy { $0.isASCII && $0.isLowercase } })
        else { return nil }
        return words
    }

    private static func chunks(of text: String) -> [String] {
        stride(from: 0, to: text.count, by: 4).map { start in
            let lower = text.index(text.startIndex, offsetBy: start)
            let upper = text.index(lower, offsetBy: 4, limitedBy: text.endIndex) ?? text.endIndex
            return String(text[lower..<upper])
        }
    }
}

/// What a QR code for a Wi-Fi memory carries.
public struct WiFiCredentials: Equatable, Sendable {
    /// Known only when the value names the network, as in "Network: Home / Password: x".
    public let networkName: String?
    public let password: String

    /// With a network name, the standard `WIFI:` payload, which a camera offers to join.
    /// Without one, just the password, which a camera offers to copy.
    public var qrPayload: String {
        guard let networkName else { return password }
        return "WIFI:T:WPA;S:\(Self.escaped(networkName));P:\(Self.escaped(password));;"
    }

    /// Reads "Network: Home, Password: x" and similar, in English and Turkish, on separate
    /// lines or on one line. Each part runs to the next label, so a password may itself
    /// contain `;`, `,` or `/`. A value with no labels is taken as the password alone; a
    /// value with spaces and no labels is not a password.
    public init?(value: String) {
        var name: String?
        var password: String?
        let labels = Self.labelPattern.matches(in: value, range: NSRange(value.startIndex..., in: value))
        for (index, match) in labels.enumerated() {
            guard let labelRange = Range(match.range(at: 1), in: value),
                  let matchRange = Range(match.range, in: value)
            else { continue }
            let end = index + 1 < labels.count
                ? Range(labels[index + 1].range, in: value)?.lowerBound ?? value.endIndex
                : value.endIndex
            var content = value[matchRange.upperBound..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            // Between two labels, a trailing "/" or "," only separated them.
            if end != value.endIndex {
                content = content.trimmingCharacters(in: CharacterSet(charactersIn: "/,;|").union(.whitespaces))
            }
            guard !content.isEmpty else { continue }
            let label = value[labelRange].lowercased()
            if Self.nameLabels.contains(label) {
                name = content
            } else {
                password = content
            }
        }

        if let password {
            self.networkName = name
            self.password = password
        } else if labels.isEmpty, !value.isEmpty, !value.contains(where: \.isWhitespace) {
            self.networkName = nil
            self.password = value
        } else {
            return nil
        }
    }

    /// A label at the start or after a separator, then `:` or `=`. Longest labels first,
    /// so "ağ adı" wins over "ağ".
    private static let labelPattern: NSRegularExpression = {
        let labels = (nameLabels.union(passwordLabels))
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        // Force-unwrapped: the pattern is built from the fixed lists above.
        return try! NSRegularExpression(
            pattern: "(?:^|(?<=[\\s/,;|]))(\(labels))\\s*[:=]",
            options: [.caseInsensitive]
        )
    }()

    private static let nameLabels: Set<String> = [
        "network", "network name", "ssid", "name", "wifi", "wi-fi", "ağ", "ağ adı", "ad",
    ]
    private static let passwordLabels: Set<String> = [
        "password", "pass", "pw", "key", "şifre", "parola", "wifi şifresi", "wi-fi şifresi",
    ]

    /// The `WIFI:` format reserves these characters.
    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\;,:\"".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
