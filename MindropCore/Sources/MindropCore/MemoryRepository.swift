import Foundation
import Observation

/// The single owner of memories: persists them and keeps Spotlight in step.
///
/// Used by the app and, for saving, by the share extension. Not by the Apple Watch, which
/// keeps no library and runs as far back as watchOS 9.
@available(watchOS 10.0, *)
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

    /// Called after every change made on this device, not after changes that came from
    /// iCloud. How iCloud sync learns there is something to send.
    public var onLocalChange: (() -> Void)?

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

    #if canImport(CoreSpotlight)
    /// The real configuration, shared by the app and the share extension. The extension
    /// passes no categorizer: it is torn down too quickly, and the app catches up on
    /// whatever it saved the next time it comes to the foreground.
    public static func live(
        categorizer: (any MemoryCategorizing)? = nil,
        spotlightExtras: SpotlightExtras = .none
    ) throws -> MemoryRepository {
        MemoryRepository(
            store: try FileMemoryStore.shared(),
            synchronizer: SpotlightSynchronizer(
                indexer: CoreSpotlightIndexer(extras: spotlightExtras),
                stateStore: try FileSpotlightSyncStateStore.shared()
            ),
            categorizer: categorizer
        )
    }
    #endif

    /// Re-reads storage. Called at launch and when returning to the foreground, since
    /// the share extension may have added memories in the meantime.
    public func load() throws {
        memories = try store.load().sorted(by: Self.isOrderedBefore)
    }

    /// Finishes any Spotlight work left over from the last run. Call this after `load`,
    /// and never before showing the UI: talking to Core Spotlight can take seconds.
    public func resumeSpotlightSync() async {
        await synchronizer.resume(allMemories: memories.filter { !$0.isDeleted })
    }

    /// Records that the user opened or copied a memory: Spotlight ranks by it.
    public func recordUse(of memory: Memory) {
        let synchronizer = synchronizer
        indexingTask = Task { await synchronizer.recordUse(of: memory) }
    }

    /// Checks that Spotlight holds every memory it should, and puts right what it lost.
    /// Nil if Spotlight could not be asked.
    public func checkSpotlight() async -> SpotlightCheck? {
        await synchronizer.verify(allMemories: memories.filter { !$0.isDeleted })
    }

    /// Indexes everything again from scratch, after the Spotlight options changed.
    public func reindexSpotlight() async {
        await synchronizer.reindexAll(memories.filter { !$0.isDeleted })
    }

    #if DEBUG
    /// Empties Spotlight without updating any record of it, as a restore would.
    public func simulateLostSpotlightIndex() async {
        await synchronizer.simulateLostIndex()
    }
    #endif

    public func memory(id: UUID) -> Memory? {
        memories.first { $0.id == id }
    }

    /// In-app filtering, newest first. An empty query and no category return every memory
    /// that has not expired or been deleted.
    public func results(for query: String, in category: MemoryCategory? = nil) -> [Memory] {
        let now = now()
        return memories.filter { memory in
            !memory.isExpired(at: now) && !memory.isDeleted
                && (category == nil || memory.category?.category == category)
                && memory.matches(query: query)
        }
    }

    /// Expired memories matching the query, most recently expired first. Kept apart from
    /// `results` so they can be recovered but never get in the way.
    public func expiredResults(for query: String) -> [Memory] {
        let now = now()
        return memories
            .filter { $0.isExpired(at: now) && !$0.isDeleted && $0.matches(query: query) }
            .sorted { ($0.expiresAt ?? .distantPast) > ($1.expiresAt ?? .distantPast) }
    }

    /// Recently Deleted, most recently deleted first.
    public var deletedMemories: [Memory] {
        memories
            .filter(\.isDeleted)
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
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
    /// the categorizer. Not an edit: the memory keeps its place in the list. Reindexed,
    /// since Spotlight shows the category's icon.
    public func setCategory(_ category: MemoryCategory?, for memory: Memory) throws {
        var stored = try store.load()
        guard let position = stored.firstIndex(where: { $0.id == memory.id }) else { return }
        stored[position].category = category.map { CategoryAssignment(category: $0, source: .manual) }
        stored[position].modifiedAt = now()
        try commit(stored)
        if synchronizer.indexesCategory { indexInBackground([stored[position]]) }
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
            stored[position].modifiedAt = now()
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
                !$0.isDeleted
                    && $0.needsCategory(categorizerVersion: categorizer.version)
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
        stored[position].modifiedAt = now()
        try commit(stored)
        if synchronizer.indexesCategory { indexInBackground([stored[position]]) }
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

    /// Deletes for good every memory past its retention: expired more than 7 days ago, or
    /// in Recently Deleted for more than 30 days. Call at launch and on returning to the
    /// foreground.
    public func purge() throws {
        let now = now()
        try deletePermanently(ids: memories.filter { $0.isDueForDeletion(at: now) }.map(\.id))
    }

    /// Moves memories to Recently Deleted: out of the list and out of Spotlight, and
    /// deleted for good 30 days later unless recovered.
    public func delete(ids: [UUID]) throws {
        let doomed = Set(ids)
        let now = now()
        var updated = memories
        var moved: [UUID] = []
        for position in updated.indices where doomed.contains(updated[position].id) && !updated[position].isDeleted {
            updated[position].deletedAt = now
            updated[position].modifiedAt = now
            moved.append(updated[position].id)
        }
        guard !moved.isEmpty else { return }
        try commit(updated)
        let synchronizer = synchronizer
        indexingTask = Task { await synchronizer.remove(ids: moved) }
    }

    /// Brings a memory back from Recently Deleted, into Spotlight again. An expired one
    /// goes back to the Expired section.
    public func recoverDeleted(_ memory: Memory) throws {
        guard let position = memories.firstIndex(where: { $0.id == memory.id }), memories[position].isDeleted else {
            return
        }
        var updated = memories
        updated[position].deletedAt = nil
        updated[position].modifiedAt = now()
        try commit(updated)
        indexInBackground([updated[position]])
    }

    /// Deletes for good, here and, through iCloud, on every device. Recently Deleted's
    /// Delete Now, and the end of every retention.
    public func deletePermanently(ids: [UUID]) throws {
        let doomed = Set(ids)
        guard memories.contains(where: { doomed.contains($0.id) }) else { return }
        try commit(memories.filter { !doomed.contains($0.id) })
        let synchronizer = synchronizer
        indexingTask = Task { await synchronizer.remove(ids: ids) }
    }

    /// Takes in what iCloud sent: changed memories, merged with this device's own version
    /// (`Memory.merged`), and memories deleted for good elsewhere. Returns what is now
    /// stored for each changed id. Not reported through `onLocalChange`.
    @discardableResult
    public func applyRemote(_ remote: [Memory], deletedIDs: [UUID]) throws -> [UUID: Memory] {
        // From storage, so a save from the share extension is merged, not overwritten.
        var stored = try store.load()
        var result: [UUID: Memory] = [:]
        var changed: [Memory] = []
        for incoming in remote {
            if let position = stored.firstIndex(where: { $0.id == incoming.id }) {
                let merged = Memory.merged(local: stored[position], remote: incoming)
                if merged != stored[position] {
                    stored[position] = merged
                    changed.append(merged)
                }
                result[incoming.id] = merged
            } else {
                stored.append(incoming)
                changed.append(incoming)
                result[incoming.id] = incoming
            }
        }
        let doomed = Set(deletedIDs)
        let removed = stored.filter { doomed.contains($0.id) }.map(\.id)
        stored.removeAll { doomed.contains($0.id) }
        guard !changed.isEmpty || !removed.isEmpty else { return result }

        try commit(stored, isLocal: false)
        let toIndex = changed.filter { !$0.isDeleted }
        let toRemove = changed.filter(\.isDeleted).map(\.id) + removed
        let synchronizer = synchronizer
        indexingTask = Task {
            await synchronizer.remove(ids: toRemove)
            await synchronizer.index(toIndex)
        }
        categorizePending()
        return result
    }

    private func commit(_ updated: [Memory], isLocal: Bool = true) throws {
        let sorted = updated.sorted(by: Self.isOrderedBefore)
        try store.save(sorted)
        memories = sorted
        if isLocal { onLocalChange?() }
    }

    /// A deleted memory is never indexed, whatever else changed about it.
    private func indexInBackground(_ memories: [Memory]) {
        let live = memories.filter { !$0.isDeleted }
        guard !live.isEmpty else { return }
        let synchronizer = synchronizer
        indexingTask = Task { await synchronizer.index(live) }
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
