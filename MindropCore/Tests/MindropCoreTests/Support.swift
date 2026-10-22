import Foundation
@testable import MindropCore

/// Records what the repository asked Core Spotlight to do, and can be made to fail.
final class SpotlightIndexerSpy: SpotlightIndexing, @unchecked Sendable {
    enum Operation: Equatable {
        case index([UUID])
        case remove([UUID])
        case removeAll
    }

    private let lock = NSLock()
    private var _operations: [Operation] = []
    private var _failures = 0
    private var _held: [String: SpotlightAttributes] = [:]
    private var _readBackFails = false

    var operations: [Operation] { lock.withLock { _operations } }

    /// What Spotlight would hold now, by identifier.
    var held: [String: SpotlightAttributes] { lock.withLock { _held } }

    /// What Spotlight was last handed for a memory.
    func attributes(of id: UUID) -> SpotlightAttributes? { held[id.uuidString] }

    /// Spotlight loses everything without Mindrop doing anything, as after a restore.
    func loseIndex() { lock.withLock { _held = [:] } }

    /// Makes reading the index back fail, as when Spotlight cannot be reached.
    func failReadingBack() { lock.withLock { _readBackFails = true } }

    /// Indexed ids that have not been removed again.
    var indexedIDs: Set<UUID> {
        var result: Set<UUID> = []
        for operation in operations {
            switch operation {
            case .index(let ids): result.formUnion(ids)
            case .remove(let ids): result.subtract(ids)
            case .removeAll: result.removeAll()
            }
        }
        return result
    }

    /// Makes the next `count` calls throw.
    func failNext(_ count: Int) {
        lock.withLock { _failures = count }
    }

    private func record(_ operation: Operation) throws {
        try lock.withLock {
            if _failures > 0 {
                _failures -= 1
                throw IndexingFailure()
            }
            _operations.append(operation)
        }
    }

    struct IndexingFailure: Error {}

    func index(_ items: [SpotlightAttributes]) async throws {
        try record(.index(items.compactMap(\.memoryID)))
        lock.withLock { for item in items { _held[item.identifier] = item } }
    }

    func remove(ids: [UUID]) async throws {
        try record(.remove(ids))
        lock.withLock { for id in ids { _held[id.uuidString] = nil } }
    }

    func removeAll() async throws {
        try record(.removeAll)
        lock.withLock { _held = [:] }
    }

    func indexedItems() async throws -> [String: String] {
        try lock.withLock {
            if _readBackFails { throw IndexingFailure() }
            return _held.mapValues(\.displayName)
        }
    }
}

@MainActor
func makeRepository(
    memories: [Memory] = [],
    store: InMemoryMemoryStore? = nil,
    indexer: SpotlightIndexerSpy = SpotlightIndexerSpy(),
    syncState: InMemorySpotlightSyncStateStore = InMemorySpotlightSyncStateStore(),
    categorizer: (any MemoryCategorizing)? = nil,
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000) }
) throws -> (MemoryRepository, InMemoryMemoryStore, SpotlightIndexerSpy) {
    let store = store ?? InMemoryMemoryStore(memories)
    let repository = MemoryRepository(
        store: store,
        synchronizer: SpotlightSynchronizer(indexer: indexer, stateStore: syncState, options: { .shipping }, now: now),
        categorizer: categorizer,
        now: now
    )
    try repository.load()
    return (repository, store, indexer)
}

func makeMemory(
    keyword: String = "wifi",
    value: String = "SuperFast2026!",
    at seconds: TimeInterval = 0,
    id: UUID = UUID()
) -> Memory {
    Memory(
        id: id,
        keyword: keyword,
        value: value,
        createdAt: Date(timeIntervalSince1970: seconds),
        updatedAt: Date(timeIntervalSince1970: seconds)
    )
}

/// A clock the test can move forward, usable from the repository's `@Sendable` closure.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date

    init(_ instant: Date = Date(timeIntervalSince1970: 1_000)) {
        self.instant = instant
    }

    var now: Date {
        get { lock.withLock { instant } }
        set { lock.withLock { instant = newValue } }
    }

    var reading: @Sendable () -> Date {
        { [self] in now }
    }
}

/// Answers from a keyword → category table, and records what it was asked.
final class CategorizerStub: MemoryCategorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: MemoryCategory]
    private var _requests: [String] = []

    let version: Int

    init(_ answers: [String: MemoryCategory] = [:], version: Int = 1) {
        self.answers = answers
        self.version = version
    }

    /// Keywords asked about, in order.
    var requests: [String] { lock.withLock { _requests } }

    func answer(_ keyword: String, with category: MemoryCategory?) {
        lock.withLock { answers[keyword] = category }
    }

    func category(for memory: Memory) async -> MemoryCategory? {
        lock.withLock {
            _requests.append(memory.keyword)
            return answers[memory.keyword]
        }
    }
}
