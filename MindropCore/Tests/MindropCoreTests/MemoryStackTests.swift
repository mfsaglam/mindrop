import Foundation
import Testing
@testable import MindropCore

@Suite("Memory Stack")
@MainActor
struct MemoryStackTests {
    @Test("Stack order survives reopening and removal preserves the original memory")
    func persistsOrderedMembership() throws {
        let directory = URL.temporaryDirectory.appending(path: "mindrop-stack-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "stack.json")
        let stack = MemoryStack(url: url)
        let folders = MemoryFolders()
        try folders.add(named: "Travel")
        let travel = try #require(folders.custom.first)
        let (repository, store, _) = try makeRepository(folders: folders, stack: stack)
        let gate = try repository.create(keyword: "departure gate", value: "C24", folderID: travel.id, addsToStack: true)
        let seat = try repository.create(keyword: "flight seat", value: "18A")

        try repository.setStackMembership([gate.id, seat.id, seat.id], included: true)
        #expect(repository.stackMemories == [gate, seat])
        #expect(throws: MemoryStack.SelectionError.invalidOrder) {
            try repository.reorderStack([gate.id, gate.id])
        }
        try repository.reorderStack([seat.id, gate.id])

        let reopened = MemoryStack(url: url)
        try reopened.load()
        let (reloaded, _, _) = try makeRepository(store: store, folders: folders, stack: reopened)
        #expect(reloaded.stackMemories == [seat, gate])
        #expect(reloaded.stackCandidates(matching: "gate").isEmpty)

        try reloaded.setStackMembership([gate.id], included: false)
        #expect(reloaded.stackMemories == [seat])
        #expect(reloaded.results(for: "", folderID: travel.id) == [gate])
        #expect(reloaded.stackCandidates(matching: "gate") == [gate])
    }

    @Test("Unavailable memories are hidden, and reordering keeps temporarily hidden slots")
    func filtersUnavailableMemories() throws {
        let clock = TestClock()
        let (repository, _, _) = try makeRepository(now: clock.reading)
        let gate = try repository.create(keyword: "departure gate", value: "C24", addsToStack: true)
        let seat = try repository.create(keyword: "flight seat", value: "18A", addsToStack: true)
        let room = try repository.create(keyword: "hotel room", value: "412", addsToStack: true)
        let temporary = try repository.create(
            keyword: "parking location", value: "B2", expiresAt: clock.now.addingTimeInterval(60), addsToStack: true
        )
        let secret = try repository.create(keyword: "account password", value: "hidden", isSensitive: true)
        let other = try repository.create(keyword: "door number", value: "302")

        #expect(throws: MemoryStack.SelectionError.unavailableMemory) {
            try repository.setStackMembership([other.id, secret.id], included: true)
        }
        #expect(!repository.isInStack(other.id))
        #expect(repository.stackCandidates(matching: "password").isEmpty)

        try repository.setSensitive(true, for: seat)
        clock.now = clock.now.addingTimeInterval(120)
        #expect(repository.stackMemories.map(\.id) == [gate.id, room.id])
        try repository.reorderStack([room.id, gate.id])
        try repository.setSensitive(false, for: seat)
        #expect(repository.stackMemories.map(\.id) == [room.id, seat.id, gate.id])
        #expect(repository.stackCandidates(matching: temporary.keyword).isEmpty)

        try repository.delete(ids: [gate.id])
        #expect(repository.stackMemories.map(\.id) == [room.id, seat.id])
        try repository.recoverDeleted(gate)
        #expect(repository.stackMemories.map(\.id) == [room.id, seat.id, gate.id])
    }

    @Test("A failed memory save rolls back Stack and folder membership")
    func rollsBackWhenCreationFails() throws {
        let stack = MemoryStack()
        let folders = MemoryFolders()
        try folders.add(named: "Travel")
        let travel = try #require(folders.custom.first)
        let (repository, store, _) = try makeRepository(folders: folders, stack: stack)
        store.saveError = InMemoryMemoryStore.Failure.disk

        #expect(throws: InMemoryMemoryStore.Failure.disk) {
            try repository.create(keyword: "departure gate", value: "C24", folderID: travel.id, addsToStack: true)
        }
        #expect(stack.ids.isEmpty)
        #expect(repository.memories.isEmpty)
    }
}
