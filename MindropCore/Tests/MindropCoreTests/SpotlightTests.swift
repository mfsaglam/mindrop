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

    @Test("Each placement puts the keyword in exactly one drawn field", arguments: KeywordPlacement.allCases)
    func placementsAreExclusive(placement: KeywordPlacement) {
        let attributes = SpotlightAttributesFactory.make(for: memory, placement: placement)

        switch placement {
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

    @Test("What ships: the keyword on the drawn line, icons and Call, not Directions")
    func shippingOptions() {
        // The only placement Spotlight finds the keyword in, on iOS 26 and 27.
        #expect(SpotlightAttributesFactory.keywordPlacement == .displayedName)
        #expect(SpotlightOptions.shipping.showsCategoryIcon)
        #expect(SpotlightOptions.shipping.offersCall)
        // Locating an address sends it to Apple Maps.
        #expect(!SpotlightOptions.shipping.offersDirections)
    }

    @Test("Options stored by an older experiment screen still decode, with today's defaults for what is missing")
    func decodesOlderOptions() throws {
        let data = Data(#"{"showsCategoryIcon":false,"contentType":"item","offersActions":true,"keywordPlacement":"bodyText"}"#.utf8)
        let options = try JSONDecoder().decode(SpotlightOptions.self, from: data)

        #expect(options == SpotlightOptions(showsCategoryIcon: false))
    }

    @Test("Body text holds the keyword alone, never the value as well")
    func bodyTextNeverRepeatsTheValue() {
        // Repeating the value here is what printed it twice in an earlier round.
        #expect(SpotlightAttributesFactory.textContent(for: memory, placement: .bodyText)?.contains("SuperFast2026!") != true)
    }

    @Test("The keyword also reaches the metadata fields Spotlight does not draw")
    func keywordReachesHiddenFields() {
        let attributes = SpotlightAttributesFactory.make(for: makeMemory(keyword: "office door", value: "482916"))

        #expect(attributes.keywords == ["office door", "office", "door"])
    }

    @Test("The searchable item carries the id, the value, the ranking signals and a far-off expiry")
    func searchableItem() {
        let memory = makeMemory(keyword: "iban", value: "TR12 3456")
        let usage = SpotlightUsage(lastUsedAt: Date(timeIntervalSince1970: 5_000), count: 3)
        let item = CoreSpotlightIndexer.searchableItem(for: SpotlightAttributesFactory.make(for: memory, usage: usage))

        #expect(item.uniqueIdentifier == memory.id.uuidString)
        #expect(item.attributeSet.displayName?.hasPrefix("TR12 3456") == true)
        #expect(item.attributeSet.keywords == ["iban"])
        // iOS 27 draws this as a second line, which would only repeat the keyword.
        #expect(item.attributeSet.alternateNames == nil)
        // Spotlight draws this one, so it must never carry anything but the keyword.
        #expect(item.attributeSet.contentDescription == nil)
        #expect(item.expirationDate == .distantFuture)
        #expect(item.attributeSet.userCreated == true)
        #expect(item.attributeSet.lastUsedDate == Date(timeIntervalSince1970: 5_000))
        #expect(item.attributeSet.rankingHint == 40)
        #expect(item.attributeSet.thumbnailData == nil)
    }

    @Test("Ranking rises quickly with the first uses and stops at 100")
    func rankingHint() {
        let hints = [1, 3, 7, 31, 1_000].map { SpotlightUsage(lastUsedAt: .now, count: $0).rankingHint }
        #expect(hints == [20, 40, 60, 100, 100])
    }

    @Test("A categorised memory shows its category's icon, unless turned off")
    func categoryIcon() {
        var memory = makeMemory(keyword: "wifi", value: "SuperFast2026!")
        #expect(SpotlightAttributesFactory.make(for: memory).iconCategory == nil)

        memory.category = CategoryAssignment(category: .network, source: .manual)
        let attributes = SpotlightAttributesFactory.make(for: memory)
        #expect(attributes.iconCategory == .network)
        #expect(SpotlightAttributesFactory.make(for: memory, options: SpotlightOptions(showsCategoryIcon: false)).iconCategory == nil)

        let icon = Data([1, 2, 3])
        #expect(CoreSpotlightIndexer.searchableItem(for: attributes, icon: icon).attributeSet.thumbnailData == icon)
    }

    @Test("A phone number in a Contacts or Family memory gets Spotlight's Call button")
    func callButton() {
        var plumber = makeMemory(keyword: "plumber", value: "+1 415 555 0132")
        #expect(SpotlightAttributesFactory.make(for: plumber).phoneNumber == nil)

        plumber.category = CategoryAssignment(category: .contact, source: .automatic)
        let attributes = SpotlightAttributesFactory.make(for: plumber)
        #expect(attributes.phoneNumber == "+1 415 555 0132")

        let item = CoreSpotlightIndexer.searchableItem(for: attributes)
        #expect(item.attributeSet.phoneNumbers == ["+1 415 555 0132"])
        #expect(item.attributeSet.supportsPhoneCall == true)
        #expect(SpotlightAttributesFactory.make(for: plumber, options: SpotlightOptions(offersCall: false)).phoneNumber == nil)
    }

    @Test("A social security number is not a phone number, whatever the detector thinks", arguments: [
        MemoryCategory.document, .finance, .code,
    ])
    func noCallForNumbersThatAreNotPhones(category: MemoryCategory) {
        var memory = makeMemory(keyword: "deniz ssn", value: "987-65-4321")
        memory.category = CategoryAssignment(category: category, source: .automatic)

        #expect(SpotlightAttributesFactory.make(for: memory).phoneNumber == nil)
    }

    @Test("Directions are offered for a place only when turned on, and carry its coordinates")
    func directions() {
        var home = makeMemory(keyword: "mom's address", value: "Bağdat Cd. 123, Kadıköy, İstanbul")
        home.category = CategoryAssignment(category: .address, source: .automatic)
        #expect(SpotlightAttributesFactory.make(for: home).address == nil)

        let attributes = SpotlightAttributesFactory.make(for: home, options: SpotlightOptions(offersDirections: true))
        #expect(attributes.address == home.value)

        let item = CoreSpotlightIndexer.searchableItem(for: attributes, location: SpotlightLocation(latitude: 41, longitude: 29))
        #expect(item.attributeSet.latitude == 41)
        #expect(item.attributeSet.supportsNavigation == true)
    }

    @Test("A sensitive memory's value never becomes a phone number or an address")
    func sensitiveHasNoActions() {
        var memory = makeMemory(keyword: "doctor", value: "+1 415 555 0132")
        memory.isSensitive = true
        memory.category = CategoryAssignment(category: .contact, source: .manual)
        #expect(SpotlightAttributesFactory.make(for: memory).phoneNumber == nil)

        memory.category = CategoryAssignment(category: .address, source: .manual)
        #expect(SpotlightAttributesFactory.make(for: memory, options: SpotlightOptions(offersDirections: true)).address == nil)
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

    @Test("A tapped result keeps what was typed, when Spotlight passes it along")
    func keepsTypedText() {
        let id = UUID()
        #expect(SpotlightRouter.destination(
            activityType: CSSearchableItemActionType,
            userInfo: [CSSearchableItemActivityIdentifier: id.uuidString, CSSearchQueryString: " wifi "]
        ) == .memory(id, query: "wifi"))
        #expect(SpotlightRouter.destination(
            activityType: CSSearchableItemActionType,
            userInfo: [CSSearchableItemActivityIdentifier: id.uuidString]
        ) == .memory(id, query: nil))
    }

    @Test("Search in Mindrop carries on the search, and an empty one is refused")
    func continuesSearch() {
        #expect(SpotlightRouter.destination(
            activityType: CSQueryContinuationActionType,
            userInfo: [CSSearchQueryString: "ev wifi"]
        ) == .search("ev wifi"))
        #expect(SpotlightRouter.destination(
            activityType: CSQueryContinuationActionType,
            userInfo: [CSSearchQueryString: "  "]
        ) == nil)
        #expect(SpotlightRouter.destination(activityType: CSQueryContinuationActionType, userInfo: nil) == nil)
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

    @Test("A shared link becomes its full address")
    func readsURLs() {
        let url = URL(string: "https://example.com/a/b?c=d")!
        #expect(SharedTextParser.text(fromLoadedItem: url) == "https://example.com/a/b?c=d")
    }

    @Test("Every shape an item provider hands back is understood")
    func readsEveryItemShape() {
        #expect(SharedTextParser.text(fromLoadedItem: "482916") == "482916")
        #expect(SharedTextParser.text(fromLoadedItem: NSAttributedString(string: "482916")) == "482916")
        #expect(SharedTextParser.text(fromLoadedItem: Data("482916".utf8)) == "482916")
    }

    @Test("Anything else is refused rather than stringified")
    func refusesUnknownItems() {
        // Describing an arbitrary object would put something like "<NSObject: 0x…>"
        // in the value field.
        #expect(SharedTextParser.text(fromLoadedItem: NSObject()) == nil)
        #expect(SharedTextParser.text(fromLoadedItem: nil) == nil)
    }
}
