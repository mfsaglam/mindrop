import Foundation
import Testing
@testable import MindropCore

@Suite("Memory validation and normalisation")
struct MemoryTests {
    @Test("A keyword and value survive creation intact")
    func createsMemory() throws {
        let memory = try Memory.make(keyword: "wifi", value: "SuperFast2026!", now: .init(timeIntervalSince1970: 10))
        #expect(memory.keyword == "wifi")
        #expect(memory.value == "SuperFast2026!")
        #expect(memory.createdAt == memory.updatedAt)
    }

    @Test("An empty or whitespace-only keyword is rejected", arguments: ["", "   ", "\n\t"])
    func rejectsEmptyKeyword(keyword: String) {
        #expect(throws: MemoryValidationError.emptyKeyword) {
            try Memory.make(keyword: keyword, value: "something", now: .now)
        }
    }

    @Test("An empty or whitespace-only value is rejected", arguments: ["", "   ", "\n"])
    func rejectsEmptyValue(value: String) {
        #expect(throws: MemoryValidationError.emptyValue) {
            try Memory.make(keyword: "wifi", value: value, now: .now)
        }
    }

    @Test("Surrounding whitespace is trimmed from both fields")
    func trimsEdges() throws {
        let memory = try Memory.make(keyword: "  office door \n", value: "  482916  ", now: .now)
        #expect(memory.keyword == "office door")
        #expect(memory.value == "482916")
    }

    @Test("Interior formatting and punctuation in a value are preserved")
    func preservesValueContents() throws {
        let value = "TR12 3456 7890\n#!$%&  spaced"
        let memory = try Memory.make(keyword: "iban", value: value, now: .now)
        #expect(memory.value == value)
    }

    @Test("Interior whitespace in a keyword is collapsed, since it is a lookup token")
    func collapsesKeywordWhitespace() throws {
        let memory = try Memory.make(keyword: "office    door", value: "482916", now: .now)
        #expect(memory.keyword == "office door")
    }

    @Test("Updating bumps the timestamp and keeps the identity and creation date")
    func updatesFields() throws {
        let original = makeMemory(at: 0)
        let edited = try original.updating(keyword: "home wifi", value: "NewPass", now: .init(timeIntervalSince1970: 50))
        #expect(edited.id == original.id)
        #expect(edited.createdAt == original.createdAt)
        #expect(edited.keyword == "home wifi")
        #expect(edited.updatedAt == .init(timeIntervalSince1970: 50))
    }

    @Test("An edit that changes nothing leaves the memory untouched")
    func noOpUpdate() throws {
        let original = makeMemory(at: 0)
        let edited = try original.updating(keyword: " wifi ", value: "SuperFast2026!", now: .init(timeIntervalSince1970: 50))
        #expect(edited == original)
    }

    @Test("In-app filtering matches keyword and value, ignoring case and accents")
    func filters() {
        let memory = makeMemory(keyword: "café", value: "Parole42")
        #expect(memory.matches(query: "CAFE"))
        #expect(memory.matches(query: "parole"))
        #expect(memory.matches(query: ""))
        #expect(!memory.matches(query: "gym"))
    }

    @Test("Every word of a search must be found, in any order, as Spotlight finds them")
    func filtersByWords() {
        let memory = makeMemory(keyword: "ev wifi şifresi", value: "kedi1234")
        #expect(memory.matches(query: "wifi ev"))
        #expect(memory.matches(query: "sifre kedi"))
        #expect(!memory.matches(query: "wifi ofis"))
    }

    @Test("Highlights cover every place each word appears, merged where they touch")
    func highlightRanges() {
        let text = "Café wifi, CAFE door"
        let ranges = SearchHighlight.ranges(of: "cafe wi", in: text).map { String(text[$0]) }
        #expect(ranges == ["Café", "wi", "CAFE"])

        let overlapping = "wifiwifi"
        #expect(SearchHighlight.ranges(of: "wif fiw", in: overlapping).map { String(overlapping[$0]) } == ["wifiwif"])
        #expect(SearchHighlight.ranges(of: "  ", in: text).isEmpty)
    }
}
