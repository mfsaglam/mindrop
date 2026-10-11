import CoreSpotlight
import Foundation
import Testing
@testable import MindropCore

@Suite("Spotlight metadata and routing")
struct SpotlightMetadataTests {
    @Test("The title leads with the value and carries the keyword, which is what Spotlight matches")
    func titleLeadsWithValue() {
        let memory = makeMemory(keyword: "wifi", value: "SuperFast2026!")
        let attributes = SpotlightAttributesFactory.make(for: memory)

        #expect(attributes.title.hasPrefix("SuperFast2026!"))
        #expect(attributes.title.contains("wifi"))
        #expect(attributes.displayName == attributes.title)
        #expect(attributes.contentDescription == "wifi")
        #expect(attributes.identifier == memory.id.uuidString)
        #expect(attributes.domainIdentifier == SpotlightAttributes.domain)
    }

    @Test("Turning the title hint off leaves the value alone")
    func valueOnlyTitleWhenDisabled() {
        // Guards the documented escape hatch in SpotlightAttributesFactory.
        let memory = makeMemory(keyword: "wifi", value: "SuperFast2026!")
        let expected = SpotlightAttributesFactory.keywordInTitle ? "SuperFast2026! — wifi" : "SuperFast2026!"
        #expect(SpotlightAttributesFactory.title(for: memory) == expected)
    }

    @Test("The keyword is also offered through every field Spotlight may consult")
    func keywordReachesEveryMatchableField() {
        let attributes = SpotlightAttributesFactory.make(for: makeMemory(keyword: "office door", value: "482916"))

        #expect(attributes.keywords == ["office door", "office", "door"])
        #expect(attributes.alternateNames == ["office door", "office", "door"])
        #expect(attributes.textContent.contains("office door"))
        #expect(attributes.textContent.contains("482916"))
    }

    @Test("A multi-word keyword is indexed whole and word by word")
    func keywordTokens() {
        #expect(SpotlightAttributesFactory.searchKeywords(for: "office door") == ["office door", "office", "door"])
        #expect(SpotlightAttributesFactory.searchKeywords(for: "wifi") == ["wifi"])
    }

    @Test("Repeated words are not indexed twice")
    func keywordTokensAreUnique() {
        #expect(SpotlightAttributesFactory.searchKeywords(for: "door Door") == ["door Door", "door", "Door"].filter { $0 != "Door" })
    }

    @Test("The searchable item carries the id, the value and a far-off expiry")
    func searchableItem() {
        let memory = makeMemory(keyword: "iban", value: "TR12 3456")
        let item = CoreSpotlightIndexer.searchableItem(for: memory)

        #expect(item.uniqueIdentifier == memory.id.uuidString)
        #expect(item.attributeSet.title?.hasPrefix("TR12 3456") == true)
        #expect(item.attributeSet.keywords == ["iban"])
        #expect(item.attributeSet.alternateNames == ["iban"])
        #expect(item.attributeSet.textContent?.contains("iban") == true)
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
