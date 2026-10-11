import CoreSpotlight
import Foundation
import Testing
@testable import MindropCore

@Suite("Spotlight metadata and routing")
struct SpotlightMetadataTests {
    private let memory = makeMemory(keyword: "wifi", value: "SuperFast2026!")

    @Test("The value always leads the drawn line, so it stays the prominent text")
    func valueLeadsTheDrawnLine() {
        let attributes = SpotlightAttributesFactory.make(for: memory)

        #expect(attributes.displayName.hasPrefix("SuperFast2026!"))
        #expect(attributes.title == attributes.displayName)
        #expect(attributes.identifier == memory.id.uuidString)
        #expect(attributes.domainIdentifier == SpotlightAttributes.domain)
    }

    @Test("Each placement puts the keyword in exactly one drawn field")
    func placementsAreExclusive() {
        let attributes = SpotlightAttributesFactory.make(for: memory)

        switch SpotlightAttributesFactory.keywordPlacement {
        case .displayedName:
            #expect(attributes.displayName == "SuperFast2026! · wifi")
            #expect(attributes.textContent == nil)
        case .bodyText:
            #expect(attributes.displayName == "SuperFast2026!")
            #expect(attributes.textContent == "wifi")
        case .hidden:
            #expect(attributes.displayName == "SuperFast2026!")
            #expect(attributes.textContent == nil)
        }
    }

    @Test("Body text holds the keyword alone, never the value as well")
    func bodyTextNeverRepeatsTheValue() {
        // Repeating the value here is what printed it twice in an earlier round.
        #expect(SpotlightAttributesFactory.textContent(for: memory)?.contains("SuperFast2026!") != true)
    }

    @Test("The keyword also reaches the metadata fields Spotlight does not draw")
    func keywordReachesHiddenFields() {
        let attributes = SpotlightAttributesFactory.make(for: makeMemory(keyword: "office door", value: "482916"))

        #expect(attributes.keywords == ["office door", "office", "door"])
        #expect(attributes.alternateNames == ["office door", "office", "door"])
    }

    @Test("The searchable item carries the id, the value and a far-off expiry")
    func searchableItem() {
        let memory = makeMemory(keyword: "iban", value: "TR12 3456")
        let item = CoreSpotlightIndexer.searchableItem(for: memory)

        #expect(item.uniqueIdentifier == memory.id.uuidString)
        #expect(item.attributeSet.displayName?.hasPrefix("TR12 3456") == true)
        #expect(item.attributeSet.keywords == ["iban"])
        #expect(item.attributeSet.alternateNames == ["iban"])
        // Spotlight draws this one, so it must never carry anything but the keyword.
        #expect(item.attributeSet.contentDescription == nil)
        #expect(item.expirationDate == .distantFuture)
    }
}

@Suite("Spotlight result routing")
struct SpotlightRouterTests {
    @Test("A Spotlight result resolves to the memory it was made from")
    func routesToMemory() {
        let id = UUID()
        let resolved = SpotlightRouter.memoryID(
            activityType: CSSearchableItemActionType,
            userInfo: [CSSearchableItemActivityIdentifier: id.uuidString]
        )
        #expect(resolved == id)
    }

    @Test("Other activities are ignored")
    func ignoresOtherActivities() {
        let id = UUID().uuidString
        #expect(SpotlightRouter.memoryID(
            activityType: "com.example.other",
            userInfo: [CSSearchableItemActivityIdentifier: id]
        ) == nil)
    }

    @Test("Missing or malformed identifiers are refused rather than guessed")
    func refusesBadIdentifiers() {
        #expect(SpotlightRouter.memoryID(activityType: CSSearchableItemActionType, userInfo: nil) == nil)
        #expect(SpotlightRouter.memoryID(
            activityType: CSSearchableItemActionType,
            userInfo: [CSSearchableItemActivityIdentifier: "not-a-uuid"]
        ) == nil)
    }
}

@Suite("Share extension input")
struct SharedTextParserTests {
    @Test("The first usable candidate becomes the value")
    func picksFirstUsable() {
        #expect(SharedTextParser.value(from: [nil, "   ", "482916"]) == "482916")
    }

    @Test("Surrounding whitespace is trimmed, interior text is kept")
    func normalises() {
        #expect(SharedTextParser.value(from: ["\n  multi\nline  \n"]) == "multi\nline")
    }

    @Test("Nothing usable means nothing is filled in")
    func returnsNilWhenEmpty() {
        #expect(SharedTextParser.value(from: [nil, "", "  "]) == nil)
    }
}
