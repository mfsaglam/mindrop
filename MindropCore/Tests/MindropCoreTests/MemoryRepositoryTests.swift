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

    @Test("Existing memories appear in General and folder assignments survive reopening")
    func foldersPreserveExistingData() throws {
        let directory = URL.temporaryDirectory.appending(path: "mindrop-folders-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "folders.json")
        let folders = MemoryFolders(url: url)
        try folders.load()
        let legacy = makeMemory(keyword: "old router")
        let (repository, store, _) = try makeRepository(memories: [legacy], folders: folders)
        #expect(repository.results(for: "", folderID: MemoryFolders.generalID) == [legacy])
        #expect(try store.load() == [legacy])

        try folders.add(named: " Work ")
        let work = try #require(folders.custom.first)
        #expect(work.name == "Work")
        try repository.move(legacy, to: work.id)
        let saved = try repository.create(keyword: "work router", value: "Office Wi-Fi", folderID: work.id)

        let reopened = MemoryFolders(url: url)
        try reopened.load()
        let (reloaded, _, _) = try makeRepository(store: store, folders: reopened)
        #expect(reopened.custom.first?.id == work.id)
        #expect(reloaded.results(for: "", folderID: MemoryFolders.generalID).isEmpty)
        #expect(Set(reloaded.results(for: "router", folderID: work.id).map(\.id)) == [legacy.id, saved.id])
        #expect(reloaded.results(for: "old router") == [legacy])
        try reloaded.move(legacy, to: MemoryFolders.generalID)
        #expect(reloaded.results(for: "", folderID: MemoryFolders.generalID) == [legacy])
    }

    @Test("Saving into an unknown folder leaves the memory store untouched")
    func unknownFolderDoesNotCreateMemory() throws {
        let (repository, store, _) = try makeRepository()
        #expect(throws: MemoryFolders.ValidationError.unknownFolder) {
            try repository.create(keyword: "wifi", value: "Office Wi-Fi", folderID: UUID())
        }
        #expect(try store.load().isEmpty)
    }

    @Test("Moving a selection updates only its live memories and preserves other folder edits")
    func moveSelectionTogether() throws {
        let directory = URL.temporaryDirectory.appending(path: "mindrop-folder-move-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "folders.json")
        let folders = MemoryFolders(url: url)
        try folders.add(named: "Work")
        let work = try #require(folders.custom.first)

        let (repository, store, _) = try makeRepository(folders: folders)
        let first = try repository.create(keyword: "door", value: "4821")
        let second = try repository.create(keyword: "desk", value: "B2")
        let unselected = try repository.create(keyword: "router", value: "Office Wi-Fi")
        let deleted = try repository.create(keyword: "old desk", value: "A3")
        try repository.delete(ids: [deleted.id])
        let other = MemoryFolders(url: url)
        try other.add(named: "Travel")

        let selection = [first.id, second.id, deleted.id, UUID()]
        #expect(throws: MemoryFolders.ValidationError.unknownFolder) {
            try repository.move(ids: selection, to: UUID())
        }
        #expect(repository.results(for: "", folderID: work.id).isEmpty)

        try repository.move(ids: selection, to: work.id)
        try other.load()
        #expect(other.custom.map(\.name) == ["Work", "Travel"])
        #expect(Set(repository.results(for: "", folderID: work.id).map(\.id)) == [first.id, second.id])
        #expect(other.folderID(for: unselected.id) == MemoryFolders.generalID)
        #expect(other.folderID(for: deleted.id) == MemoryFolders.generalID)
        #expect(try store.load().count == 4)

        try repository.move(ids: [first.id, second.id], to: MemoryFolders.generalID)
        try other.load()
        #expect(other.folderID(for: first.id) == MemoryFolders.generalID)
        #expect(other.folderID(for: second.id) == MemoryFolders.generalID)
    }

    @Test("Folder deletion keeps its records recoverable and preserves independent saves")
    func folderDeletionIsRecoverable() async throws {
        let directory = URL.temporaryDirectory.appending(path: "mindrop-folder-delete-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appending(path: "folders.json")
        let folders = MemoryFolders(url: folderURL)
        try folders.add(named: "Work")
        let work = try #require(folders.custom.first)

        let store = FileMemoryStore(url: directory.appending(path: "memories.json"))
        let indexer = SpotlightIndexerSpy()
        let clock = TestClock()
        let repository = MemoryRepository(
            store: store, synchronizer: SpotlightSynchronizer(
                indexer: indexer, stateStore: InMemorySpotlightSyncStateStore(), options: { .shipping }, now: clock.reading
            ), folders: folders, now: clock.reading
        )
        let workMemory = try repository.create(keyword: "office wifi", value: "Guest", folderID: work.id)
        await repository.indexingTask?.value
        let older = try repository.create(keyword: "office phone", value: "555-0100", folderID: work.id)
        await repository.indexingTask?.value
        try repository.delete(ids: [older.id])
        await repository.indexingTask?.value
        let originalDeletion = clock.now
        clock.now = clock.now.addingTimeInterval(60)
        let expired = try repository.create(
            keyword: "temporary code", value: "1234", expiresAt: originalDeletion, folderID: work.id
        )
        await repository.indexingTask?.value
        let shared = makeMemory(keyword: "shared memory")
        _ = try store.update { $0 + [shared] }

        try repository.deleteFolder(work.id)
        await repository.indexingTask?.value

        let reopened = MemoryFolders(url: folderURL)
        try reopened.load()
        #expect(reopened.custom.isEmpty)
        #expect(try store.load().contains(shared))
        #expect(Set(repository.deletedMemories.map(\.id)) == [workMemory.id, older.id, expired.id])
        #expect(repository.memory(id: older.id)?.deletedAt == originalDeletion)
        #expect(repository.memory(id: workMemory.id)?.deletedAt == clock.now)
        #expect(repository.expiredResults(for: "").isEmpty)
        #expect(!indexer.indexedIDs.contains(workMemory.id))

        try repository.recoverDeleted(workMemory)
        #expect(repository.results(for: "", folderID: MemoryFolders.generalID).contains { $0.id == workMemory.id })
    }

    @Test("A folder stays intact if its records cannot be moved to Recently Deleted")
    func failedFolderDeletionCanBeRetried() throws {
        let (repository, store, _) = try makeRepository()
        try repository.folders.add(named: "Work")
        let work = try #require(repository.folders.custom.first)
        let memory = try repository.create(keyword: "office wifi", value: "Guest", folderID: work.id)
        store.saveError = InMemoryMemoryStore.Failure.disk

        #expect(throws: InMemoryMemoryStore.Failure.disk) {
            try repository.deleteFolder(work.id)
        }
        #expect(repository.folders.custom.map(\.id) == [work.id])
        #expect(repository.results(for: "", folderID: work.id) == [memory])
        #expect(repository.deletedMemories.isEmpty)

        store.saveError = nil
        try repository.deleteFolder(work.id)
        #expect(repository.folders.custom.isEmpty)
        #expect(repository.deletedMemories.map(\.id) == [memory.id])
    }

    @Test("General is protected and an empty custom folder can be removed")
    func canDeleteOnlyCustomFolders() throws {
        let (repository, _, _) = try makeRepository()
        let memory = try repository.create(keyword: "home wifi", value: "Guest")
        try repository.folders.add(named: "Empty")
        let empty = try #require(repository.folders.custom.first)

        #expect(throws: MemoryFolders.ValidationError.unknownFolder) {
            try repository.deleteFolder(MemoryFolders.generalID)
        }
        try repository.deleteFolder(empty.id)
        #expect(repository.folders.custom.isEmpty)
        #expect(repository.results(for: "") == [memory])
        #expect(repository.deletedMemories.isEmpty)
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

    #if os(macOS)
    @Test("Importing a Mac share can retry without losing or duplicating a memory")
    func importMacSharesCanRetry() throws {
        let (repository, store, _) = try makeRepository()
        let existing = try repository.create(keyword: "office door", value: "482916")
        let incoming = try Memory.make(keyword: "Apple", value: "https://www.apple.com/", now: .now)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = CoordinatedFile(url: directory.appending(path: "pending-memories.json"))
        let pending = try JSONEncoder.mindrop.encode([incoming])
        try inbox.write(pending)

        store.saveError = InMemoryMemoryStore.Failure.disk
        #expect(throws: InMemoryMemoryStore.Failure.disk) {
            try repository.importMacShares(from: inbox)
        }
        #expect(try inbox.read() == pending)
        #expect(repository.memories.map(\.id) == [existing.id])

        store.saveError = nil
        try repository.importMacShares(from: inbox)
        #expect(try inbox.read() == JSONEncoder.mindrop.encode([Memory]()))

        // The inbox write can fail after the library has already stored the share.
        try inbox.write(pending)
        store.saveError = InMemoryMemoryStore.Failure.disk
        try repository.importMacShares(from: inbox)
        #expect(repository.memories.map(\.id) == [incoming.id, existing.id])
        #expect(try inbox.read() == JSONEncoder.mindrop.encode([Memory]()))
    }
    #endif
}

extension InMemoryMemoryStore {
    enum Failure: Error { case disk }
}
