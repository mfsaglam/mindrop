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

    /// The categorisation pass in progress, if any. Exposed for the same reason as
    /// `indexingTask`.
    public private(set) var categorizationTask: Task<Void, Never>?

    private let store: MemoryStore
    private let synchronizer: SpotlightSynchronizer
    private let categorizer: (any MemoryCategorizing)?
    private let now: @Sendable () -> Date

    /// Text the categorizer already declined this run, so a memory it cannot place is
    /// not sent again on every foregrounding. Keyed by content: an edit earns a retry.
    private var declinedCategorizations: Set<CategorizationKey> = []
    private var needsAnotherCategorizationPass = false

    public init(
        store: MemoryStore,
        synchronizer: SpotlightSynchronizer,
        categorizer: (any MemoryCategorizing)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.synchronizer = synchronizer
        self.categorizer = categorizer
        self.now = now
    }

    /// The real configuration, shared by the app and the share extension. The extension
    /// passes no categorizer: it is torn down too quickly, and the app catches up on
    /// whatever it saved the next time it comes to the foreground.
    public static func live(categorizer: (any MemoryCategorizing)? = nil) throws -> MemoryRepository {
        MemoryRepository(
            store: try FileMemoryStore.shared(),
            synchronizer: SpotlightSynchronizer(
                indexer: CoreSpotlightIndexer(),
                stateStore: try FileSpotlightSyncStateStore.shared()
            ),
            categorizer: categorizer
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

    /// In-app filtering, newest first. An empty query and no category return every memory
    /// that has not expired.
    public func results(for query: String, in category: MemoryCategory? = nil) -> [Memory] {
        let now = now()
        return memories.filter { memory in
            !memory.isExpired(at: now)
                && (category == nil || memory.category?.category == category)
                && memory.matches(query: query)
        }
    }

    /// Expired memories matching the query, most recently expired first. Kept apart from
    /// `results` so they can be recovered but never get in the way.
    public func expiredResults(for query: String) -> [Memory] {
        let now = now()
        return memories
            .filter { $0.isExpired(at: now) && $0.matches(query: query) }
            .sorted { ($0.expiresAt ?? .distantPast) > ($1.expiresAt ?? .distantPast) }
    }

    /// The categories at least one live memory is in, in declaration order — what a
    /// filter offers.
    public var categoriesInUse: [MemoryCategory] {
        let used = Set(results(for: "").compactMap(\.category?.category))
        return MemoryCategory.allCases.filter(used.contains)
    }

    @discardableResult
    public func create(keyword: String, value: String, expiresAt: Date? = nil, isSensitive: Bool = false) throws -> Memory {
        let memory = try insert(keyword: keyword, value: value, expiresAt: expiresAt, isSensitive: isSensitive)
        indexInBackground([memory])
        categorizePending()
        return memory
    }

    /// Creates a memory and waits for Spotlight to accept it.
    ///
    /// The share extension is torn down as soon as it completes its request, so it
    /// cannot leave indexing running in the background the way the app can.
    @discardableResult
    public func createAwaitingIndex(
        keyword: String,
        value: String,
        expiresAt: Date? = nil,
        isSensitive: Bool = false
    ) async throws -> Memory {
        let memory = try insert(keyword: keyword, value: value, expiresAt: expiresAt, isSensitive: isSensitive)
        await synchronizer.index([memory])
        return memory
    }

    private func insert(keyword: String, value: String, expiresAt: Date?, isSensitive: Bool) throws -> Memory {
        let memory = try Memory.make(
            keyword: keyword,
            value: value,
            now: now(),
            expiresAt: expiresAt,
            isSensitive: isSensitive
        )
        var updated = memories
        updated.append(memory)
        try commit(updated)
        return memory
    }

    /// Saves an edit of the text, keeping the memory's expiry and sensitivity.
    @discardableResult
    public func update(_ memory: Memory, keyword: String, value: String) throws -> Memory {
        try update(memory, keyword: keyword, value: value, expiresAt: memory.expiresAt, isSensitive: memory.isSensitive)
    }

    /// Saves an edit. Returns the stored memory, unchanged if nothing differed.
    @discardableResult
    public func update(
        _ memory: Memory,
        keyword: String,
        value: String,
        expiresAt: Date?,
        isSensitive: Bool
    ) throws -> Memory {
        let edited = try memory.updating(
            keyword: keyword,
            value: value,
            expiresAt: expiresAt,
            isSensitive: isSensitive,
            now: now()
        )
        guard edited != memory, let position = memories.firstIndex(where: { $0.id == memory.id }) else {
            return memory
        }
        var updated = memories
        updated[position] = edited
        try commit(updated)
        indexInBackground([edited])
        categorizePending()
        return edited
    }

    /// Files a memory under a category the user picked, or with `nil` hands it back to
    /// the categorizer. Not an edit: the memory keeps its place in the list, and Spotlight
    /// is not touched because categories are not indexed.
    public func setCategory(_ category: MemoryCategory?, for memory: Memory) throws {
        var stored = try store.load()
        guard let position = stored.firstIndex(where: { $0.id == memory.id }) else { return }
        stored[position].category = category.map { CategoryAssignment(category: $0, source: .manual) }
        try commit(stored)
        if category == nil {
            declinedCategorizations.remove(CategorizationKey(stored[position]))
            categorizePending()
        }
    }

    /// Drops every automatic category and categorises everything again. Manual choices
    /// stay. For trying out a changed prompt without bumping the categorizer version.
    public func resetAutomaticCategories() throws {
        var stored = try store.load()
        for position in stored.indices where stored[position].category?.source == .automatic {
            stored[position].category = nil
        }
        try commit(stored)
        declinedCategorizations.removeAll()
        categorizePending()
    }

    /// Categorises every memory that has no category yet, or one from an older categorizer. Cheap to call often: it does
    /// nothing without a categorizer, and coalesces with a pass already running.
    public func categorizePending() {
        guard let categorizer else { return }
        guard categorizationTask == nil else {
            needsAnotherCategorizationPass = true
            return
        }
        categorizationTask = Task {
            await categorizeUntilSettled(using: categorizer)
            categorizationTask = nil
        }
    }

    private func categorizeUntilSettled(using categorizer: any MemoryCategorizing) async {
        repeat {
            needsAnotherCategorizationPass = false
            let pending = memories.filter {
                $0.needsCategory(categorizerVersion: categorizer.version)
                    && !declinedCategorizations.contains(CategorizationKey($0))
            }
            for memory in pending {
                if let category = await categorizer.category(for: memory) {
                    // Nothing to do if this fails: the memory stays uncategorised and the
                    // next pass tries again.
                    try? apply(category, version: categorizer.version, to: memory)
                } else {
                    declinedCategorizations.insert(CategorizationKey(memory))
                }
            }
        } while needsAnotherCategorizationPass
    }

    /// Stores an automatic category, unless the memory changed while the model was
    /// thinking. Reads storage first so it cannot overwrite what the share extension
    /// saved in the meantime.
    private func apply(_ category: MemoryCategory, version: Int, to original: Memory) throws {
        var stored = try store.load()
        guard let position = stored.firstIndex(where: { $0.id == original.id }),
              CategorizationKey(stored[position]) == CategorizationKey(original),
              stored[position].needsCategory(categorizerVersion: version)
        else { return }
        stored[position].category = CategoryAssignment(category: category, source: .automatic, version: version)
        try commit(stored)
    }

    /// Moves a memory's expiry, or with `nil` keeps it forever. Recovering an expired
    /// memory is this with `nil`: it comes back for good, not on a new timer. Reindexed,
    /// because Spotlight drops an item at its expiry.
    public func setExpiry(_ expiresAt: Date?, for memory: Memory) throws {
        guard let current = self.memory(id: memory.id) else { return }
        try update(
            current,
            keyword: current.keyword,
            value: current.value,
            expiresAt: expiresAt,
            isSensitive: current.isSensitive
        )
    }

    /// Hides a memory's value from Spotlight, or shows it there again. Reindexed, since
    /// that is the whole point; not an edit, so the memory keeps its place in the list.
    public func setSensitive(_ isSensitive: Bool, for memory: Memory) throws {
        guard let current = self.memory(id: memory.id) else { return }
        try update(
            current,
            keyword: current.keyword,
            value: current.value,
            expiresAt: current.expiresAt,
            isSensitive: isSensitive
        )
    }

    /// Deletes for good every memory that expired more than
    /// `MemoryLifetime.expiredRetention` ago. Call at launch and on returning to the
    /// foreground.
    public func deleteExpired() throws {
        let now = now()
        let doomed = memories.filter { $0.deletionDate.map { $0 <= now } ?? false }
        try delete(ids: doomed.map(\.id))
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

    private struct CategorizationKey: Hashable {
        let id: UUID
        let keyword: String
        let value: String

        init(_ memory: Memory) {
            id = memory.id
            keyword = memory.keyword
            value = memory.value
        }
    }

    private static func isOrderedBefore(_ lhs: Memory, _ rhs: Memory) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
    }
}
