import Foundation
import os

/// Keeps the Spotlight index in step with stored memories.
///
/// Every mutation is recorded as pending *before* it is attempted and cleared only
/// once Core Spotlight confirms it, so a failure (or the app being killed mid-write)
/// leaves a breadcrumb that `resume` picks up on the next launch.
@MainActor
public final class SpotlightSynchronizer {
    /// Raise this when the indexed metadata changes, to force one reconciliation pass.
    /// 2: the keyword moved into the title, after metadata-only matching failed on device.
    /// 3: dropped `contentDescription` and `textContent`, which Spotlight was drawing.
    /// 4: the keyword is back in `displayName`, which is the field that actually matches.
    /// 5: keyword moved to `textContent`, to find out whether that field matches too.
    /// 6: it does not — back to the keyword in `displayName`, the only matched field.
    /// 9: sensitive memories show the keyword and a lock instead of the value. (7 and 8
    /// were used by discarded experiments, and may still be stored on test devices.)
    /// 10: ranking signals (created by the user, last used, and how much); no
    /// `alternateNames`, which iOS 27 drew as a second line repeating the keyword; the
    /// category's icon; phone numbers for the Call button.
    /// 11: the keyword back on the drawn line on every device, where a Debug experiment
    /// had moved it to the second line (not found by Spotlight, on iOS 27 too).
    /// 12: category icons redrawn with Iconsax symbols.
    public static let currentIndexFormatVersion = 12

    private let indexer: SpotlightIndexing
    private let stateStore: SpotlightSyncStateStore
    private var state: SpotlightSyncState
    private let options: @Sendable () -> SpotlightOptions
    private let now: @Sendable () -> Date
    private let log = Logger(subsystem: "mfsaglam.Mindrop", category: "spotlight")

    public init(
        indexer: SpotlightIndexing,
        stateStore: SpotlightSyncStateStore,
        options: @escaping @Sendable () -> SpotlightOptions = { .current },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.indexer = indexer
        self.stateStore = stateStore
        self.options = options
        self.now = now
        self.state = (try? stateStore.load()) ?? SpotlightSyncState()
    }

    public var hasPendingWork: Bool { state.hasPendingWork }

    /// Whether a change of category changes what Spotlight is handed: its icon, and
    /// whether a number gets a Call button.
    public var indexesCategory: Bool {
        let options = options()
        return options.showsCategoryIcon || options.offersCall || options.offersDirections
    }

    /// What Spotlight is handed for a memory, with this device's usage of it.
    func attributes(for memory: Memory, options: SpotlightOptions) -> SpotlightAttributes {
        SpotlightAttributesFactory.make(for: memory, options: options, usage: state.usage[memory.id])
    }

    public func index(_ memories: [Memory]) async {
        guard !memories.isEmpty else { return }
        let ids = memories.map(\.id)
        mutateState {
            $0.pendingIndex.formUnion(ids)
            $0.pendingDelete.subtract(ids)
        }
        let options = options()
        do {
            try await indexer.index(memories.map { attributes(for: $0, options: options) })
            mutateState { $0.pendingIndex.subtract(ids) }
        } catch {
            // Left pending on purpose; `resume` retries it.
            log.error("Indexing failed, \(ids.count, privacy: .public) item(s) left pending")
        }
    }

    public func remove(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        mutateState {
            $0.pendingDelete.formUnion(ids)
            $0.pendingIndex.subtract(ids)
        }
        do {
            try await indexer.remove(ids: ids)
            mutateState { $0.pendingDelete.subtract(ids) }
        } catch {
            log.error("Index removal failed, \(ids.count, privacy: .public) item(s) left pending")
        }
    }

    /// Call once at launch. Reindexes everything only when the metadata format or the
    /// options changed; otherwise it retries whatever was left unfinished, then checks
    /// that Spotlight still holds what it should (`verify`).
    public func resume(allMemories: [Memory]) async {
        if state.indexFormatVersion != Self.currentIndexFormatVersion
            || (state.indexedOptions ?? .shipping) != options() {
            await reindexAll(allMemories)
            return
        }
        if state.hasPendingWork {
            let byID = Dictionary(uniqueKeysWithValues: allMemories.map { ($0.id, $0) })
            let retryIndex = state.pendingIndex.compactMap { byID[$0] }
            // A pending id with no memory behind it was deleted before indexing succeeded.
            let vanished = state.pendingIndex.filter { byID[$0] == nil }
            let retryDelete = state.pendingDelete.union(vanished)

            await remove(ids: Array(retryDelete))
            await index(retryIndex)
        }
        await verify(allMemories: allMemories)
    }

    /// Compares what Spotlight holds with what it should, and puts right the difference:
    /// a memory missing or out of date there is indexed again, an item with no memory
    /// behind it is removed.
    ///
    /// Spotlight's index is not part of a backup, but Mindrop's own record that everything
    /// was indexed is, so after restoring an iPhone or moving to a new one that record
    /// says all is well over an empty index. iOS can also rebuild the index by itself.
    /// Nil if Spotlight could not be asked.
    @discardableResult
    public func verify(allMemories: [Memory]) async -> SpotlightCheck? {
        let indexed: [String: String]
        do {
            indexed = try await indexer.indexedItems()
        } catch {
            log.error("Could not read back the Spotlight index")
            return nil
        }
        let now = now()
        let options = options()
        let kept = allMemories.filter { !$0.isDeleted }
        // Spotlight drops an expired memory by itself, at its expiry.
        let expected = kept.filter { !$0.isExpired(at: now) }
        let outOfStep = expected.filter { indexed[$0.id.uuidString] != attributes(for: $0, options: options).displayName }
        let keptIDs = Set(kept.map(\.id.uuidString))
        let strays = indexed.keys.filter { !keptIDs.contains($0) }.compactMap(UUID.init(uuidString:))

        mutateState { state in
            let keptIDs = Set(kept.map(\.id))
            state.usage = state.usage.filter { keptIDs.contains($0.key) }
        }
        await remove(ids: strays)
        await index(outOfStep)

        let check = SpotlightCheck(expected: expected.count, repaired: outOfStep.count, removed: strays.count)
        if check.repaired > 0 || check.removed > 0 {
            log.notice("Spotlight check: \(check.repaired, privacy: .public) of \(check.expected, privacy: .public) put back, \(check.removed, privacy: .public) removed")
        }
        return check
    }

    /// Records that the user opened or copied a memory, and tells Spotlight, whose ranking
    /// reads it. A memory out of Spotlight only has its usage recorded.
    public func recordUse(of memory: Memory) async {
        mutateState { state in
            let count = (state.usage[memory.id]?.count ?? 0) + 1
            state.usage[memory.id] = SpotlightUsage(lastUsedAt: now(), count: count)
        }
        guard !memory.isDeleted, !memory.isExpired(at: now()) else { return }
        await index([memory])
    }

    #if DEBUG
    /// Empties Spotlight behind the synchronizer's back, the way a restore leaves it, so
    /// the launch check can be seen putting it right.
    public func simulateLostIndex() async {
        try? await indexer.removeAll()
    }
    #endif

    /// Removes everything Mindrop indexed and indexes it again with the current options.
    public func reindexAll(_ memories: [Memory]) async {
        let options = options()
        do {
            try await indexer.removeAll()
            try await indexer.index(memories.map { attributes(for: $0, options: options) })
            mutateState {
                $0.pendingIndex = []
                $0.pendingDelete = []
                $0.indexFormatVersion = Self.currentIndexFormatVersion
                $0.indexedOptions = options
            }
        } catch {
            // Version is deliberately not bumped, so the next launch tries again.
            log.error("Full reindex failed; will retry on next launch")
        }
    }

    private func mutateState(_ change: (inout SpotlightSyncState) -> Void) {
        change(&state)
        do {
            try stateStore.save(state)
        } catch {
            log.error("Could not persist Spotlight sync state")
        }
    }
}

/// What a check of the index found.
public struct SpotlightCheck: Equatable, Sendable {
    /// Memories that should be in Spotlight.
    public let expected: Int
    /// Of those, how many were missing or out of date and were indexed again.
    public let repaired: Int
    /// Items in Spotlight with no memory behind them, removed.
    public let removed: Int
}
