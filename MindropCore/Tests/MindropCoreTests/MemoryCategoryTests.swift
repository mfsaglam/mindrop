import Foundation
import Testing
@testable import MindropCore

@Suite("Categorising memories")
@MainActor
struct MemoryCategoryTests {
    @Test("A new memory is categorised automatically")
    func createCategorises() async throws {
        let categorizer = CategorizerStub(["wifi": .network])
        let (repository, store, _) = try makeRepository(categorizer: categorizer)
        let memory = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        await repository.categorizationTask?.value

        let expected = CategoryAssignment(category: .network, source: .automatic, version: 1)
        #expect(repository.memory(id: memory.id)?.category == expected)
        #expect(try store.load().first?.category == expected)
    }

    @Test("A category, automatic or picked, reaches Spotlight as the result's icon")
    func categoryReachesSpotlight() async throws {
        let categorizer = CategorizerStub(["wifi": .network])
        let (repository, _, indexer) = try makeRepository(categorizer: categorizer)
        let memory = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        await repository.categorizationTask?.value
        await repository.indexingTask?.value
        #expect(indexer.attributes(of: memory.id)?.iconCategory == .network)

        try repository.setCategory(.home, for: memory)
        await repository.indexingTask?.value
        #expect(indexer.attributes(of: memory.id)?.iconCategory == .home)
    }

    @Test("Categorising does not move a memory up the list")
    func categorisingKeepsOrder() async throws {
        let older = makeMemory(keyword: "iban", value: "TR12", at: 10)
        let newer = makeMemory(keyword: "wifi", value: "x", at: 20)
        let categorizer = CategorizerStub(["iban": .finance])
        let (repository, _, _) = try makeRepository(memories: [older, newer], categorizer: categorizer)

        repository.categorizePending()
        await repository.categorizationTask?.value

        #expect(repository.memories.map(\.id) == [newer.id, older.id])
        #expect(repository.memory(id: older.id)?.updatedAt == older.updatedAt)
    }

    @Test("Without a categorizer nothing is categorised")
    func noCategorizer() async throws {
        let (repository, _, _) = try makeRepository()
        let memory = try repository.create(keyword: "wifi", value: "x")
        #expect(repository.categorizationTask == nil)
        #expect(repository.memory(id: memory.id)?.category == nil)
    }

    @Test("A memory the categorizer declines is not asked about again until edited")
    func declinedIsNotRetried() async throws {
        let categorizer = CategorizerStub()
        let (repository, _, _) = try makeRepository(categorizer: categorizer)
        let memory = try repository.create(keyword: "thing", value: "x")
        await repository.categorizationTask?.value

        repository.categorizePending()
        await repository.categorizationTask?.value
        #expect(categorizer.requests == ["thing"])

        categorizer.answer("thing 2", with: .other)
        try repository.update(memory, keyword: "thing 2", value: "x")
        await repository.categorizationTask?.value
        #expect(categorizer.requests == ["thing", "thing 2"])
        #expect(repository.memory(id: memory.id)?.category?.category == .other)
    }

    @Test("Editing drops an automatic category and categorises again")
    func editRecategorises() async throws {
        let categorizer = CategorizerStub(["wifi": .network, "iban": .finance])
        let (repository, _, _) = try makeRepository(categorizer: categorizer)
        let memory = try repository.create(keyword: "wifi", value: "x")
        await repository.categorizationTask?.value

        let stored = try #require(repository.memory(id: memory.id))
        try repository.update(stored, keyword: "iban", value: "TR12")
        await repository.categorizationTask?.value

        #expect(repository.memory(id: memory.id)?.category?.category == .finance)
    }

    @Test("A category the user picked survives edits and is never overwritten")
    func manualCategoryIsKept() async throws {
        let categorizer = CategorizerStub(["wifi": .network, "home wifi": .network])
        let (repository, _, _) = try makeRepository(categorizer: categorizer)
        let memory = try repository.create(keyword: "wifi", value: "x")
        await repository.categorizationTask?.value

        try repository.setCategory(.address, for: memory)
        let stored = try #require(repository.memory(id: memory.id))
        try repository.update(stored, keyword: "home wifi", value: "y")
        await repository.categorizationTask?.value

        #expect(repository.memory(id: memory.id)?.category == CategoryAssignment(category: .address, source: .manual))
        #expect(categorizer.requests == ["wifi"])
    }

    @Test("Clearing a manual category hands the memory back to the categorizer")
    func clearingManualRecategorises() async throws {
        let categorizer = CategorizerStub(["wifi": .network])
        let (repository, _, _) = try makeRepository(categorizer: categorizer)
        let memory = try repository.create(keyword: "wifi", value: "x")
        await repository.categorizationTask?.value
        try repository.setCategory(.other, for: memory)

        try repository.setCategory(nil, for: memory)
        await repository.categorizationTask?.value

        #expect(repository.memory(id: memory.id)?.category == CategoryAssignment(category: .network, source: .automatic, version: 1))
    }

    @Test("A result for text that changed meanwhile is thrown away")
    func staleResultIsDiscarded() async throws {
        let original = makeMemory(keyword: "wifi", value: "x")
        let categorizer = CategorizerStub(["wifi": .network])
        let store = InMemoryMemoryStore([original])
        let (repository, _, _) = try makeRepository(store: store, categorizer: categorizer)

        // Another process edits the memory while the model is working.
        var edited = original
        edited.keyword = "locker"
        try store.save([edited])

        repository.categorizePending()
        await repository.categorizationTask?.value
        #expect(try store.load() == [edited])
    }

    @Test("Categorising keeps memories another process saved in the meantime")
    func keepsConcurrentAdditions() async throws {
        let original = makeMemory(keyword: "wifi", value: "x")
        let store = InMemoryMemoryStore([original])
        let (repository, _, _) = try makeRepository(store: store, categorizer: CategorizerStub(["wifi": .network]))

        let fromExtension = makeMemory(keyword: "plate", value: "34 ABC 12", at: 50)
        try store.save([original, fromExtension])

        repository.categorizePending()
        await repository.categorizationTask?.value
        #expect(Set(try store.load().map(\.id)) == [original.id, fromExtension.id])
    }

    @Test("Filtering by category, and listing the categories in use")
    func filtersByCategory() async throws {
        let categorizer = CategorizerStub(["wifi": .network, "iban": .finance, "office wifi": .network])
        let (repository, _, _) = try makeRepository(categorizer: categorizer)
        try repository.create(keyword: "wifi", value: "a")
        try repository.create(keyword: "iban", value: "b")
        try repository.create(keyword: "office wifi", value: "c")
        await repository.categorizationTask?.value

        #expect(repository.categoriesInUse == [.network, .finance])
        #expect(repository.results(for: "", in: .network).map(\.keyword).sorted() == ["office wifi", "wifi"])
        #expect(repository.results(for: "office", in: .network).map(\.keyword) == ["office wifi"])
        #expect(repository.results(for: "", in: .vehicle).isEmpty)
    }

    @Test("Files written before categories existed still load")
    func decodesLegacyFile() throws {
        let json = """
        [{"id":"7D3F0B7E-1A2B-4C5D-8E9F-0A1B2C3D4E5F","keyword":"wifi","value":"x",
          "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}]
        """
        let memories = try JSONDecoder.mindrop.decode([Memory].self, from: Data(json.utf8))
        #expect(memories.first?.category == nil)
    }

    @Test("A better categorizer redoes its predecessor's choices, but not the user's")
    func newVersionRecategorises() async throws {
        let old = makeMemory(keyword: "atlas ssn", value: "123-45-6789", at: 10)
        let legacy = makeMemory(keyword: "atlas birthday", value: "12.03.2019", at: 20)
        let chosen = makeMemory(keyword: "visa", value: "4111", at: 30)
        var memories = [old, legacy, chosen]
        memories[0].category = CategoryAssignment(category: .vehicle, source: .automatic, version: 1)
        memories[1].category = CategoryAssignment(category: .other, source: .automatic)
        memories[2].category = CategoryAssignment(category: .account, source: .manual)

        let categorizer = CategorizerStub(
            ["atlas ssn": .document, "atlas birthday": .people, "visa": .finance],
            version: 2
        )
        let (repository, _, _) = try makeRepository(memories: memories, categorizer: categorizer)
        repository.categorizePending()
        await repository.categorizationTask?.value

        #expect(repository.memory(id: old.id)?.category == CategoryAssignment(category: .document, source: .automatic, version: 2))
        #expect(repository.memory(id: legacy.id)?.category?.category == .people)
        #expect(repository.memory(id: chosen.id)?.category?.category == .account)
        #expect(categorizer.requests.sorted() == ["atlas birthday", "atlas ssn"])

        // Settled: a second pass asks nothing.
        repository.categorizePending()
        await repository.categorizationTask?.value
        #expect(categorizer.requests.count == 2)
    }

    @Test("Recategorising redoes automatic choices, including declined ones, and keeps manual ones")
    func resetRecategorises() async throws {
        let categorizer = CategorizerStub(["wifi": .other])
        let (repository, _, _) = try makeRepository(categorizer: categorizer)
        let automatic = try repository.create(keyword: "wifi", value: "x")
        let declined = try repository.create(keyword: "thing", value: "y")
        let manual = try repository.create(keyword: "visa", value: "z")
        await repository.categorizationTask?.value
        try repository.setCategory(.finance, for: manual)

        categorizer.answer("wifi", with: .network)
        categorizer.answer("thing", with: .home)
        try repository.resetAutomaticCategories()
        await repository.categorizationTask?.value

        #expect(repository.memory(id: automatic.id)?.category?.category == .network)
        #expect(repository.memory(id: declined.id)?.category?.category == .home)
        #expect(repository.memory(id: manual.id)?.category?.source == .manual)
    }

    @Test("A card number is banking without asking the model", arguments: [
        "4111 1111 1111 1111", "4111111111111111", "5555-4444-3333-1111", "4111 1111 1111 1111 12/28 123",
    ])
    func cardIsEvident(value: String) {
        #expect(MemoryCategory.evident(fromValue: value) == .finance)
    }

    @Test("Other long numbers are not mistaken for cards", arguments: [
        "4111 1111 1111 1112", "12345678901", "123-45-6789", "011", "TR33 0006 1005 1978 6457 8413 26",
    ])
    func nonCardNumbersAreNotEvident(value: String) {
        #expect(MemoryCategory.evident(fromValue: value) == nil)
    }

    @Test("A bare web link is a link without asking the model", arguments: [
        "https://example.com/menemen", "HTTP://example.com",
    ])
    func linkIsEvident(value: String) {
        #expect(MemoryCategory.evident(fromValue: value) == .link)
    }

    @Test("Anything else is left to the model", arguments: [
        "SuperFast2026!", "see https://example.com", "mailto:me@example.com", "example.com", "https://",
    ])
    func otherValuesAreNotEvident(value: String) {
        #expect(MemoryCategory.evident(fromValue: value) == nil)
    }
}

@Suite("Grouping the list by category")
struct CategoryGroupingTests {
    private func memory(_ keyword: String, _ category: MemoryCategory?, at seconds: TimeInterval) -> Memory {
        var memory = makeMemory(keyword: keyword, at: seconds)
        memory.category = category.map { CategoryAssignment(category: $0, source: .automatic) }
        return memory
    }

    @Test("Sections follow the category order, uncategorised last, and keep each memory's order")
    func groupsInOrder() {
        let memories = [
            memory("unsorted", nil, at: 50),
            memory("iban", .finance, at: 40),
            memory("wifi", .network, at: 30),
            memory("card", .finance, at: 20),
            memory("router", .network, at: 10),
        ]
        let sections = memories.groupedByCategory()

        #expect(sections.map(\.category) == [.network, .finance, nil])
        #expect(sections.map { $0.memories.map(\.keyword) } == [["wifi", "router"], ["iban", "card"], ["unsorted"]])
    }

    @Test("No memories, no sections")
    func emptyHasNoSections() {
        #expect([Memory]().groupedByCategory().isEmpty)
    }
}
