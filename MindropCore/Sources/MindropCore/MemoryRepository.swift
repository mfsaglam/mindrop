import Foundation
import Observation

/// The single owner of memories: persists them and keeps Spotlight in step.
///
/// Used by the app and, for saving, by the share extension.
@MainActor
@Observable
public final class MemoryRepository {
    /// Most recently touched first.
    public private(set) var memories: [Memory] = []

    /// The most recent background indexing work. Exposed so callers that must not
    /// outlive it — and tests — can wait for Spotlight to settle.
    public private(set) var indexingTask: Task<Void, Never>?

    private let store: MemoryStore
    private let synchronizer: SpotlightSynchronizer
    private let now: @Sendable () -> Date

    public init(
        store: MemoryStore,
        synchronizer: SpotlightSynchronizer,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.synchronizer = synchronizer
        self.now = now
    }

    /// The real configuration, shared by the app and the share extension.
    public static func live() throws -> MemoryRepository {
        MemoryRepository(
            store: try FileMemoryStore.shared(),
            synchronizer: SpotlightSynchronizer(
                indexer: CoreSpotlightIndexer(),
                stateStore: try FileSpotlightSyncStateStore.shared()
            )
        )
    }

    /// Re-reads storage. Called at launch and when returning to the foreground, since
    /// the share extension may have added memories in the meantime.
    public func load() throws {
        memories = try store.load().sorted(by: Self.isOrderedBefore)
    }

    /// Finishes any Spotlight work left over from the last run. Call this after `load`,
    /// and never before showing the UI: talking to Core Spotlight can take seconds.
    public func resumeSpotlightSync() async {
        await synchronizer.resume(allMemories: memories)
    }

    public func memory(id: UUID) -> Memory? {
        memories.first { $0.id == id }
    }

    /// In-app filtering, newest first. An empty query returns everything.
    public func results(for query: String) -> [Memory] {
        memories.filter { $0.matches(query: query) }
    }

    @discardableResult
    public func create(keyword: String, value: String) throws -> Memory {
        let memory = try insert(keyword: keyword, value: value)
        indexInBackground([memory])
        return memory
    }

    /// Creates a memory and waits for Spotlight to accept it.
    ///
    /// The share extension is torn down as soon as it completes its request, so it
    /// cannot leave indexing running in the background the way the app can.
    @discardableResult
    public func createAwaitingIndex(keyword: String, value: String) async throws -> Memory {
        let memory = try insert(keyword: keyword, value: value)
        await synchronizer.index([memory])
        return memory
    }

    private func insert(keyword: String, value: String) throws -> Memory {
        let memory = try Memory.make(keyword: keyword, value: value, now: now())
        var updated = memories
        updated.append(memory)
        try commit(updated)
        return memory
    }

    /// Saves an edit. Returns the stored memory, unchanged if nothing differed.
    @discardableResult
    public func update(_ memory: Memory, keyword: String, value: String) throws -> Memory {
        let edited = try memory.updating(keyword: keyword, value: value, now: now())
        guard edited != memory, let position = memories.firstIndex(where: { $0.id == memory.id }) else {
            return memory
        }
        var updated = memories
        updated[position] = edited
        try commit(updated)
        indexInBackground([edited])
        return edited
    }

    public func delete(ids: [UUID]) throws {
        let doomed = Set(ids)
        guard memories.contains(where: { doomed.contains($0.id) }) else { return }
        try commit(memories.filter { !doomed.contains($0.id) })
        let synchronizer = synchronizer
        indexingTask = Task { await synchronizer.remove(ids: ids) }
    }

    private func commit(_ updated: [Memory]) throws {
        let sorted = updated.sorted(by: Self.isOrderedBefore)
        try store.save(sorted)
        memories = sorted
    }

    private func indexInBackground(_ memories: [Memory]) {
        let synchronizer = synchronizer
        indexingTask = Task { await synchronizer.index(memories) }
    }

    private static func isOrderedBefore(_ lhs: Memory, _ rhs: Memory) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
    }
}
