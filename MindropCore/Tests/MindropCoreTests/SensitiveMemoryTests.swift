import Foundation
import Testing
@testable import MindropCore

@Suite("Sensitive memories")
@MainActor
struct SensitiveMemoryTests {
    @Test("Spotlight gets the keyword and a lock, never the value")
    func spotlightHidesValue() {
        var memory = makeMemory(keyword: "atlas ssn", value: "123-45-6789")
        memory.isSensitive = true
        let attributes = SpotlightAttributesFactory.make(for: memory)

        #expect(attributes.displayName == "atlas ssn · 🔒")
        #expect(attributes.title == attributes.displayName)
        #expect(attributes.textContent == nil)
        #expect(!attributes.displayName.contains("123"))
        #expect(attributes.keywords.contains("atlas ssn"))
    }

    @Test("New memories are not sensitive unless asked")
    func offByDefault() throws {
        let (repository, _, _) = try makeRepository()
        let wifi = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        let ssn = try repository.create(keyword: "atlas ssn", value: "123-45-6789", isSensitive: true)

        #expect(!wifi.isSensitive)
        #expect(ssn.isSensitive)
    }

    @Test("Turning it on or off reindexes, keeps the memory's place and keeps its category")
    func toggleIsNotAnEdit() async throws {
        let clock = TestClock()
        let (repository, store, indexer) = try makeRepository(now: clock.reading)
        let ssn = try repository.create(keyword: "atlas ssn", value: "123-45-6789")
        try repository.setCategory(.document, for: ssn)
        await repository.indexingTask?.value

        clock.now = clock.now.addingTimeInterval(60)
        try repository.setSensitive(true, for: ssn)

        let hidden = try #require(repository.memory(id: ssn.id))
        #expect(hidden.isSensitive)
        #expect(hidden.updatedAt == ssn.updatedAt)
        #expect(hidden.category?.category == .document)
        #expect(try store.load().first?.isSensitive == true)
        await repository.indexingTask?.value
        #expect(indexer.operations.filter { $0 == .index([ssn.id]) }.count == 2)

        try repository.setSensitive(false, for: hidden)
        #expect(repository.memory(id: ssn.id)?.isSensitive == false)
    }

    @Test("Editing the text or the expiry leaves it sensitive")
    func editsKeepIt() throws {
        let (repository, _, _) = try makeRepository()
        let ssn = try repository.create(keyword: "atlas ssn", value: "123-45-6789", isSensitive: true)

        let edited = try repository.update(ssn, keyword: "atlas ssn", value: "123-45-6780")
        #expect(edited.isSensitive)
        try repository.setExpiry(.distantFuture, for: edited)
        #expect(repository.memory(id: ssn.id)?.isSensitive == true)
    }

    @Test("In-app search finds a sensitive memory by keyword, not by its hidden value")
    func searchSkipsHiddenValue() throws {
        let (repository, _, _) = try makeRepository()
        let ssn = try repository.create(keyword: "atlas ssn", value: "123-45-6789", isSensitive: true)
        let card = try repository.create(keyword: "visa", value: "4111 1111 1111 1111")

        #expect(repository.results(for: "atlas") == [ssn])
        #expect(repository.results(for: "123").isEmpty)
        #expect(repository.results(for: "4111") == [card])
    }

    @Test("Memories saved before sensitivity existed still decode, as not sensitive")
    func legacyDecoding() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","keyword":"wifi","value":"x","createdAt":0,"updatedAt":0}]"#
        let memories = try JSONDecoder().decode([Memory].self, from: Data(json.utf8))
        #expect(memories.first?.isSensitive == false)
    }

    @Test("The flag survives a round trip through storage")
    func roundTrip() throws {
        var memory = makeMemory(keyword: "atlas ssn", value: "123-45-6789")
        memory.isSensitive = true
        memory.expiresAt = Date(timeIntervalSince1970: 5_000)
        let data = try JSONEncoder.mindrop.encode([memory])
        #expect(try JSONDecoder.mindrop.decode([Memory].self, from: data) == [memory])
    }
}
