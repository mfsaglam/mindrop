import Foundation
import Testing
@testable import MindropCore

@Suite("Recently Deleted")
@MainActor
struct RecentlyDeletedTests {
    private let day: TimeInterval = 24 * 60 * 60

    @Test("Deleting moves a memory to Recently Deleted and out of Spotlight")
    func deleteIsRecoverable() async throws {
        let clock = TestClock()
        let (repository, store, indexer) = try makeRepository(now: clock.reading)
        let wifi = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        let door = try repository.create(keyword: "office door", value: "4821#")
        await repository.indexingTask?.value

        try repository.delete(ids: [wifi.id])

        #expect(repository.results(for: "") == [door])
        #expect(repository.deletedMemories.map(\.id) == [wifi.id])
        #expect(try store.load().first { $0.id == wifi.id }?.deletedAt == clock.now)
        await repository.indexingTask?.value
        #expect(indexer.indexedIDs == [door.id])
    }

    @Test("Recovering brings it back to the list and to Spotlight")
    func recover() async throws {
        let (repository, _, indexer) = try makeRepository()
        let wifi = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        try repository.delete(ids: [wifi.id])
        await repository.indexingTask?.value

        try repository.recoverDeleted(wifi)

        #expect(repository.results(for: "").map(\.id) == [wifi.id])
        #expect(repository.deletedMemories.isEmpty)
        await repository.indexingTask?.value
        #expect(indexer.indexedIDs == [wifi.id])
    }

    @Test("A deleted memory is deleted for good after 30 days, not before")
    func purgedAfterThirtyDays() throws {
        let clock = TestClock()
        let (repository, _, _) = try makeRepository(now: clock.reading)
        let wifi = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        try repository.delete(ids: [wifi.id])

        clock.now = clock.now.addingTimeInterval(29 * day)
        try repository.purge()
        #expect(repository.deletedMemories.count == 1)

        clock.now = clock.now.addingTimeInterval(day)
        try repository.purge()
        #expect(repository.memories.isEmpty)
    }

    @Test("A deleted memory that has expired waits the full 30 days, and stays out of Expired")
    func deletedAndExpired() throws {
        let clock = TestClock()
        let (repository, _, _) = try makeRepository(now: clock.reading)
        let hotel = try repository.create(keyword: "hotel room", value: "412", expiresAt: clock.now.addingTimeInterval(day))
        try repository.delete(ids: [hotel.id])

        clock.now = clock.now.addingTimeInterval(10 * day)
        try repository.purge()
        #expect(repository.deletedMemories.count == 1)
        #expect(repository.expiredResults(for: "").isEmpty)
    }

    @Test("Every change stamps the memory's change time; text edits also its edit time")
    func changesAreStamped() throws {
        let clock = TestClock()
        let (repository, _, _) = try makeRepository(now: clock.reading)
        let wifi = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        #expect(wifi.modifiedAt == clock.now)

        clock.now = clock.now.addingTimeInterval(60)
        try repository.setSensitive(true, for: wifi)
        let hidden = try #require(repository.memory(id: wifi.id))
        #expect(hidden.modifiedAt == clock.now)
        #expect(hidden.updatedAt == wifi.updatedAt)

        clock.now = clock.now.addingTimeInterval(60)
        try repository.setCategory(.network, for: hidden)
        #expect(repository.memory(id: wifi.id)?.modifiedAt == clock.now)
    }

    @Test("Local changes are reported, changes from iCloud are not")
    func localChangesReported() throws {
        let (repository, _, _) = try makeRepository()
        var reports = 0
        repository.onLocalChange = { reports += 1 }

        let wifi = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        #expect(reports == 1)

        var remote = wifi
        remote.value = "Changed"
        remote.updatedAt = wifi.updatedAt.addingTimeInterval(1)
        remote.modifiedAt = remote.updatedAt
        try repository.applyRemote([remote], deletedIDs: [])
        #expect(reports == 1)
        #expect(repository.memory(id: wifi.id)?.value == "Changed")
    }

    @Test("Changes from iCloud update Spotlight, and deletions for good remove memories")
    func applyRemote() async throws {
        let (repository, _, indexer) = try makeRepository()
        let wifi = try repository.create(keyword: "wifi", value: "SuperFast2026!")
        let door = try repository.create(keyword: "office door", value: "4821#")
        await repository.indexingTask?.value

        let newcomer = makeMemory(keyword: "iban", value: "TR12", at: 5_000)
        var deleted = door
        deleted.deletedAt = Date(timeIntervalSince1970: 5_000)
        deleted.modifiedAt = Date(timeIntervalSince1970: 5_000)
        try repository.applyRemote([newcomer, deleted], deletedIDs: [wifi.id])

        #expect(repository.results(for: "").map(\.id) == [newcomer.id])
        #expect(repository.deletedMemories.map(\.id) == [door.id])
        #expect(repository.memory(id: wifi.id) == nil)
        await repository.indexingTask?.value
        #expect(indexer.indexedIDs == [newcomer.id])
    }
}
