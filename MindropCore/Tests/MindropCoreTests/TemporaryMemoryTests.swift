import Foundation
import Testing
@testable import MindropCore

@Suite("Temporary memories")
@MainActor
struct TemporaryMemoryTests {
    private let day: TimeInterval = 24 * 60 * 60

    @Test("Each lifetime gives the expected expiry, and forever gives none")
    func lifetimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 0) // 1 Jan 1970
        let date = Date(timeIntervalSince1970: 12_345)

        #expect(MemoryLifetime.forever.expiry(from: now, calendar: calendar) == nil)
        #expect(MemoryLifetime.day.expiry(from: now, calendar: calendar) == now.addingTimeInterval(day))
        #expect(MemoryLifetime.week.expiry(from: now, calendar: calendar) == now.addingTimeInterval(7 * day))
        #expect(MemoryLifetime.month.expiry(from: now, calendar: calendar) == now.addingTimeInterval(31 * day))
        #expect(MemoryLifetime.until(date).expiry(from: now, calendar: calendar) == date)
    }

    @Test("An expired memory leaves the list and shows under Expired")
    func expiredMovesOut() throws {
        let clock = TestClock()
        let (repository, _, _) = try makeRepository(now: clock.reading)
        let hotel = try repository.create(keyword: "hotel room", value: "412", expiresAt: clock.now.addingTimeInterval(day))
        let wifi = try repository.create(keyword: "wifi", value: "SuperFast2026!")

        #expect(Set(repository.results(for: "")) == [hotel, wifi])
        #expect(repository.expiredResults(for: "").isEmpty)

        clock.now = clock.now.addingTimeInterval(day)
        #expect(repository.results(for: "") == [wifi])
        #expect(repository.expiredResults(for: "") == [hotel])
        #expect(repository.expiredResults(for: "wifi").isEmpty)
    }

    @Test("Expired memories are deleted for good seven days after expiring, not before")
    func deletedAfterRetention() async throws {
        let clock = TestClock()
        let (repository, store, indexer) = try makeRepository(now: clock.reading)
        let hotel = try repository.create(keyword: "hotel room", value: "412", expiresAt: clock.now.addingTimeInterval(day))
        let wifi = try repository.create(keyword: "wifi", value: "SuperFast2026!")

        clock.now = clock.now.addingTimeInterval(7 * day)
        try repository.deleteExpired()
        #expect(repository.memories.count == 2)

        clock.now = clock.now.addingTimeInterval(day)
        try repository.deleteExpired()
        #expect(repository.memories == [wifi])
        #expect(try store.load() == [wifi])
        await repository.indexingTask?.value
        #expect(indexer.operations.contains(.remove([hotel.id])))
    }

    @Test("Recovering an expired memory keeps it forever, and reindexes it")
    func recoverKeepsForever() async throws {
        let clock = TestClock()
        let (repository, _, indexer) = try makeRepository(now: clock.reading)
        let hotel = try repository.create(keyword: "hotel room", value: "412", expiresAt: clock.now.addingTimeInterval(day))
        await repository.indexingTask?.value

        clock.now = clock.now.addingTimeInterval(2 * day)
        try repository.setExpiry(nil, for: hotel)

        let recovered = try #require(repository.memory(id: hotel.id))
        #expect(recovered.expiresAt == nil)
        #expect(repository.results(for: "") == [recovered])
        #expect(repository.expiredResults(for: "").isEmpty)
        await repository.indexingTask?.value
        #expect(indexer.operations.filter { $0 == .index([hotel.id]) }.count == 2)
    }

    @Test("Changing only the expiry keeps the memory's place and category")
    func expiryChangeIsNotAnEdit() throws {
        let clock = TestClock()
        let (repository, _, _) = try makeRepository(now: clock.reading)
        let hotel = try repository.create(keyword: "hotel room", value: "412", expiresAt: clock.now.addingTimeInterval(day))
        try repository.setCategory(.home, for: hotel)

        clock.now = clock.now.addingTimeInterval(60)
        try repository.setExpiry(clock.now.addingTimeInterval(7 * day), for: hotel)

        let stored = try #require(repository.memory(id: hotel.id))
        #expect(stored.updatedAt == hotel.updatedAt)
        #expect(stored.category?.category == .home)
        #expect(stored.expiresAt == clock.now.addingTimeInterval(7 * day))
    }

    @Test("Spotlight is told to drop a temporary memory at its expiry")
    func spotlightExpiration() {
        let expiry = Date(timeIntervalSince1970: 5_000)
        var memory = makeMemory()
        #expect(SpotlightAttributesFactory.make(for: memory).expirationDate == .distantFuture)

        memory.expiresAt = expiry
        #expect(SpotlightAttributesFactory.make(for: memory).expirationDate == expiry)
    }

    @Test("Memories saved before expiry existed still decode, as kept forever")
    func legacyDecoding() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","keyword":"wifi","value":"x","createdAt":0,"updatedAt":0}]"#
        let memories = try JSONDecoder().decode([Memory].self, from: Data(json.utf8))
        #expect(memories.first?.expiresAt == nil)
    }
}
