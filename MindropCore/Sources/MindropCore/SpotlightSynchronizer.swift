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
    public static let currentIndexFormatVersion = 6

    private let indexer: SpotlightIndexing
    private let stateStore: SpotlightSyncStateStore
    private var state: SpotlightSyncState
    private let log = Logger(subsystem: "mfsaglam.Mindrop", category: "spotlight")

    public init(indexer: SpotlightIndexing, stateStore: SpotlightSyncStateStore) {
        self.indexer = indexer
        self.stateStore = stateStore
        self.state = (try? stateStore.load()) ?? SpotlightSyncState()
    }

    public var hasPendingWork: Bool { state.hasPendingWork }

    public func index(_ memories: [Memory]) async {
        guard !memories.isEmpty else { return }
        let ids = memories.map(\.id)
        mutateState {
            $0.pendingIndex.formUnion(ids)
            $0.pendingDelete.subtract(ids)
        }
        do {
            try await indexer.index(memories)
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

    /// Call once at launch. Reindexes everything only when the metadata format changed;
    /// otherwise it just retries whatever was left unfinished.
    public func resume(allMemories: [Memory]) async {
        if state.indexFormatVersion != Self.currentIndexFormatVersion {
            await reindexAll(allMemories)
            return
        }
        guard state.hasPendingWork else { return }

        let byID = Dictionary(uniqueKeysWithValues: allMemories.map { ($0.id, $0) })
        let retryIndex = state.pendingIndex.compactMap { byID[$0] }
        // A pending id with no memory behind it was deleted before indexing succeeded.
        let vanished = state.pendingIndex.filter { byID[$0] == nil }
        let retryDelete = state.pendingDelete.union(vanished)

        await remove(ids: Array(retryDelete))
        await index(retryIndex)
    }

    private func reindexAll(_ memories: [Memory]) async {
        do {
            try await indexer.removeAll()
            try await indexer.index(memories)
            mutateState {
                $0.pendingIndex = []
                $0.pendingDelete = []
                $0.indexFormatVersion = Self.currentIndexFormatVersion
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
