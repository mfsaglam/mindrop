import Foundation
import FoundationModels
import MindropCore

/// Categorises memories with the on-device Apple Intelligence model. Nothing leaves the
/// iPhone. On a device without Apple Intelligence, or with it turned off, every answer
/// is nil and memories simply stay uncategorised.
nonisolated struct AppleIntelligenceCategorizer: MemoryCategorizing {
    /// 2: added people and home, the name and digits rules, permissive guardrails, and
    /// the card number rule. Version 1's choices are redone.
    let version = 2

    /// Receives every request in Debug builds; nil in Release.
    let log: CategorizationLog?

    init(log: CategorizationLog? = nil) {
        self.log = log
    }

    /// Enough of a long value to recognise it; the rest only costs time.
    private static let valuePrefixLength = 200

    /// The description lines, kept apart so a reply that echoes a description instead of
    /// a name can be traced back to its category.
    private static let descriptions: [(MemoryCategory, String)] = [
        (.document, "identity and official numbers: passport, national ID, social security, driving licence, insurance policy, membership and serial numbers"),
        (.health, "blood type, allergies, medication, vaccinations, doctors"),
        (.people, "birthdays, anniversaries, ages, clothing and shoe sizes, and other personal details about a family member or friend that fit no category above"),
        (.finance, "bank and credit card numbers, IBANs, card expiry dates, tax numbers"),
        (.code, "a secret you enter to get access: PINs, door, gate, locker, padlock and alarm codes"),
        (.home, "how to operate appliances and devices at home: button sequences, settings, maintenance steps such as descaling or resetting"),
        (.network, "Wi-Fi names and passwords, routers, VPNs"),
        (.account, "logins, usernames and passwords for apps and websites"),
        (.contact, "phone numbers and email addresses"),
        (.address, "postal addresses, locations, directions, parking spots"),
        (.vehicle, "licence plates, VINs, tyre sizes, car or bike details"),
        (.link, "web addresses"),
        (.other, "anything else"),
    ]

    private static let instructions = """
        You file short personal notes. Each note is a keyword the person searches for, \
        and the value they saved under it. Decide what kind of information the note holds, \
        then pick the single category that fits best:

        \(descriptions.map { "\($0.0.rawValue): \($0.1)" }.joined(separator: "\n"))

        Rules:
        - Keywords often start with a person's name, such as "atlas ssn" or "deniz birthday". \
        The name tells you whose note it is, never the category. Atlas, Mercedes or Jaguar \
        in front of other words is a person's name, not a car.
        - Being made of digits does not make something a code. A social security number is \
        a document, a card number is finance, a date is people, a button pattern is home.
        - The note may be in any language.

        Reply with exactly one word, which must be one of: \
        \(descriptions.map(\.0.rawValue).joined(separator: ", ")).
        """

    func category(for memory: Memory) async -> MemoryCategory? {
        let started = Date()
        let prompt = """
            Keyword: \(memory.keyword)
            Value: \(memory.value.prefix(Self.valuePrefixLength))
            """
        func record(_ outcome: CategorizationLog.Outcome, response: String? = nil) async {
            await log?.record(.init(
                memoryID: memory.id, keyword: memory.keyword, date: started,
                duration: Date().timeIntervalSince(started), prompt: prompt,
                response: response, outcome: outcome
            ))
        }

        if let evident = MemoryCategory.evident(fromValue: memory.value) {
            await record(.rule(evident))
            return evident
        }

        // Permissive guardrails: the default ones refuse exactly what people keep here —
        // card numbers, passports, allergies, birthdays — as "may contain sensitive
        // content". This mode only allows a plain text reply, not guided generation,
        // hence the one-word answer and the parsing below. The general model, not the
        // `.contentTagging` adapter, which filed lockers and links under other.
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else {
            await record(.unavailable(String(describing: model.availability)))
            return nil
        }

        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy))
            let category = Self.parse(response.content)
            await record(category.map(CategorizationLog.Outcome.model) ?? .unparsed, response: response.content)
            return category
        } catch {
            // The model being busy, an unsupported language, a refusal: all mean "no
            // category for now", never an error to show.
            await record(.failed(String(describing: error)))
            return nil
        }
    }

    /// The first category name in the reply, or failing that the category whose
    /// description the reply quotes ("blood type", "identity and official numbers").
    static func parse(_ reply: String) -> MemoryCategory? {
        let words = reply.lowercased().split { !$0.isLetter }.map(String.init)
        if let name = words.lazy.compactMap(MemoryCategory.init(rawValue:)).first { return name }
        let phrase = reply.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !phrase.isEmpty else { return nil }
        return descriptions.first { $0.1.lowercased().contains(phrase) }?.0
    }
}
