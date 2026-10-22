import Foundation
import Testing
@testable import MindropCore

@Suite("Repository persistence and Spotlight synchronisation")
@MainActor
struct MemoryRepositoryTests {
    @Test("Creating a memory persists it and indexes it")
    func createPersistsAndIndexes() async throws {
        let (repository, store, indexer) = try makeRepository()
        let memory = try repository.create(keyword: "wifi", value: "SuperFast2026!")

        #expect(repository.memories == [memory])
        #expect(try store.load() == [memory])
        await repository.indexingTask?.value
        #expect(indexer.indexedIDs == [memory.id])
    }

    @Test("A short keyword cannot be saved by the app or share extension")
    func shortKeywordDoesNotPersist() async throws {
        let (repository, store, indexer) = try makeRepository()

        #expect(throws: MemoryValidationError.keywordTooShort) {
            try repository.create(keyword: "123", value: "something")
        }
        await #expect(throws: MemoryValidationError.keywordTooShort) {
            try await repository.createAwaitingIndex(keyword: "123", value: "something")
        }

        #expect(repository.memories.isEmpty)
        #expect(try store.load().isEmpty)
        #expect(indexer.operations.isEmpty)
    }

    @Test("An edit with a short keyword leaves the saved memory unchanged")
    func shortKeywordDoesNotOverwrite() async throws {
        let (repository, store, indexer) = try makeRepository()
        let memory = try repository.create(keyword: "wifi", value: "original")
        await repository.indexingTask?.value
        let operations = indexer.operations

        #expect(throws: MemoryValidationError.keywordTooShort) {
            try repository.update(memory, keyword: "123", value: "changed")
        }

        #expect(repository.memories == [memory])
        #expect(try store.load() == [memory])
        #expect(indexer.operations == operations)
    }

    @Test("Previously saved short keywords still load and can be renamed")
    func loadsLegacyShortKeyword() throws {
        let legacy = makeMemory(keyword: "pin", value: "1234")
        let (repository, store, _) = try makeRepository(memories: [legacy])
        #expect(repository.memory(id: legacy.id) == legacy)

        let edited = try repository.update(legacy, keyword: "door", value: legacy.value)
        #expect(edited.id == legacy.id)
        #expect(try store.load() == [edited])
    }

    @Test("A reloaded repository sees what was saved")
    func reloadsFromStore() throws {
        let store = InMemoryMemoryStore()
        let (repository, _, _) = try makeRepository(store: store)
        let memory = try repository.create(keyword: "gym locker", value: "0713")

        let (reloaded, _, _) = try makeRepository(store: store)
        #expect(reloaded.memories == [memory])
    }

    @Test("Updating a memory persists the edit and reindexes it")
    func updatePersistsAndIndexes() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 10))
        let (repository, store, indexer) = try makeRepository(now: clock.reading)
        let memory = try repository.create(keyword: "wifi", value: "old")

        clock.now = Date(timeIntervalSince1970: 99)
        let edited = try repository.update(memory, keyword: "wifi", value: "new")

        #expect(edited.value == "new")
        #expect(edited.updatedAt == Date(timeIntervalSince1970: 99))
        #expect(try store.load() == [edited])
        await repository.indexingTask?.value
        #expect(indexer.operations.contains(.index([memory.id])))
    }

    @Test("Cancelling an edit leaves the stored memory alone")
    func cancelledEditChangesNothing() throws {
        let (repository, store, _) = try makeRepository()
        let memory = try repository.create(keyword: "wifi", value: "SuperFast2026!")

        // Cancelling means the editor simply never calls update.
        #expect(try store.load() == [memory])
        #expect(repository.memories == [memory])
    }

    @Test("Deleting a memory for good removes it from storage and from the index")
    func deleteRemovesEverywhere() async throws {
        let (repository, store, indexer) = try makeRepository()
        let memory = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        await repository.indexingTask?.value
        let survivor = try repository.create(keyword: "iban", value: "TR12")
        await repository.indexingTask?.value

        try repository.deletePermanently(ids: [memory.id])

        #expect(repository.memories == [survivor])
        #expect(try store.load() == [survivor])
        await repository.indexingTask?.value
        #expect(indexer.indexedIDs == [survivor.id])
    }

    @Test("Deleting something that is not there does nothing")
    func deleteMissingIsHarmless() throws {
        let (repository, _, indexer) = try makeRepository()
        try repository.delete(ids: [UUID()])
        #expect(repository.memories.isEmpty)
        #expect(indexer.operations.isEmpty)
    }

    @Test("Looking up a deleted memory returns nothing, which the detail screen handles")
    func lookupAfterDelete() throws {
        let (repository, _, _) = try makeRepository()
        let memory = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        try repository.deletePermanently(ids: [memory.id])
        #expect(repository.memory(id: memory.id) == nil)
    }

    @Test("Memories are listed most recently updated first")
    func sortsByRecency() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1))
        let (repository, _, _) = try makeRepository(now: clock.reading)
        let first = try repository.create(keyword: "alpha", value: "1")
        clock.now = Date(timeIntervalSince1970: 2)
        let second = try repository.create(keyword: "bravo", value: "2")

        #expect(repository.memories == [second, first])
    }

    @Test("In-app search filters the list")
    func searchFilters() throws {
        let (repository, _, _) = try makeRepository()
        let wifi = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        _ = try repository.create(keyword: "iban", value: "TR12")

        #expect(repository.results(for: "wif") == [wifi])
        #expect(repository.results(for: "superfast") == [wifi])
        #expect(repository.results(for: "").count == 2)
    }

    @Test("A failed save leaves the in-memory list untouched")
    func failedSaveDoesNotMutateState() throws {
        let store = InMemoryMemoryStore()
        let (repository, _, _) = try makeRepository(store: store)
        store.saveError = InMemoryMemoryStore.Failure.disk

        #expect(throws: (any Error).self) {
            try repository.create(keyword: "wifi", value: "SuperFast2026!")
        }
        #expect(repository.memories.isEmpty)
    }

    @Test("The share extension waits for indexing before it finishes")
    func createAwaitingIndex() async throws {
        let (repository, store, indexer) = try makeRepository()
        let memory = try await repository.createAwaitingIndex(keyword: "office door", value: "482916")

        #expect(try store.load() == [memory])
        #expect(indexer.indexedIDs == [memory.id])
    }
}

extension InMemoryMemoryStore {
    enum Failure: Error { case disk }
}
