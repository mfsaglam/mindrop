import Foundation
import Testing
@testable import MindropCore

@Suite("Spotlight index recovery")
@MainActor
struct SpotlightSynchronizerTests {
    private func makeSynchronizer(
        indexer: SpotlightIndexerSpy = SpotlightIndexerSpy(),
        state: InMemorySpotlightSyncStateStore
    ) -> SpotlightSynchronizer {
        SpotlightSynchronizer(indexer: indexer, stateStore: state, options: { .shipping })
    }

    @Test("A fresh install indexes everything once, then stops reindexing")
    func firstRunReconcilesOnce() async {
        let indexer = SpotlightIndexerSpy()
        let state = InMemorySpotlightSyncStateStore()
        let memories = [makeMemory(keyword: "a"), makeMemory(keyword: "b")]

        await makeSynchronizer(indexer: indexer, state: state).resume(allMemories: memories)
        #expect(indexer.operations == [.removeAll, .index(memories.map(\.id))])

        // A later launch with the same metadata format must not reindex.
        await makeSynchronizer(indexer: indexer, state: state).resume(allMemories: memories)
        #expect(indexer.operations.count == 2)
    }

    @Test("A failed index is retried on the next launch")
    func retriesFailedIndexing() async {
        let indexer = SpotlightIndexerSpy()
        let state = InMemorySpotlightSyncStateStore(
            SpotlightSyncState(indexFormatVersion: SpotlightSynchronizer.currentIndexFormatVersion)
        )
        let memory = makeMemory()

        indexer.failNext(1)
        let first = makeSynchronizer(indexer: indexer, state: state)
        await first.index([memory])
        #expect(indexer.indexedIDs.isEmpty)
        #expect(first.hasPendingWork)

        await makeSynchronizer(indexer: indexer, state: state).resume(allMemories: [memory])
        #expect(indexer.indexedIDs == [memory.id])
    }

    @Test("A failed deletion is retried on the next launch")
    func retriesFailedDeletion() async {
        let indexer = SpotlightIndexerSpy()
        let state = InMemorySpotlightSyncStateStore(
            SpotlightSyncState(indexFormatVersion: SpotlightSynchronizer.currentIndexFormatVersion)
        )
        let memory = makeMemory()
        await makeSynchronizer(indexer: indexer, state: state).index([memory])

        indexer.failNext(1)
        await makeSynchronizer(indexer: indexer, state: state).remove(ids: [memory.id])
        #expect(indexer.indexedIDs == [memory.id])

        await makeSynchronizer(indexer: indexer, state: state).resume(allMemories: [])
        #expect(indexer.indexedIDs.isEmpty)
    }

    @Test("A memory deleted before its indexing succeeded is removed, not resurrected")
    func dropsVanishedPendingItems() async {
        let indexer = SpotlightIndexerSpy()
        let memory = makeMemory()
        let state = InMemorySpotlightSyncStateStore(
            SpotlightSyncState(
                indexFormatVersion: SpotlightSynchronizer.currentIndexFormatVersion,
                pendingIndex: [memory.id]
            )
        )

        await makeSynchronizer(indexer: indexer, state: state).resume(allMemories: [])
        #expect(indexer.operations == [.remove([memory.id])])
    }

    @Test("A failed full reindex is attempted again on the next launch")
    func retriesFullReindex() async {
        let indexer = SpotlightIndexerSpy()
        let state = InMemorySpotlightSyncStateStore()
        let memory = makeMemory()

        indexer.failNext(1)
        await makeSynchronizer(indexer: indexer, state: state).resume(allMemories: [memory])
        #expect(indexer.indexedIDs.isEmpty)

        await makeSynchronizer(indexer: indexer, state: state).resume(allMemories: [memory])
        #expect(indexer.indexedIDs == [memory.id])
    }

    @Test("After a restore the index is empty though the record says all is well: everything is put back")
    func putsBackALostIndex() async {
        let indexer = SpotlightIndexerSpy()
        let state = InMemorySpotlightSyncStateStore()
        let memories = [makeMemory(keyword: "a"), makeMemory(keyword: "b")]
        await makeSynchronizer(indexer: indexer, state: state).resume(allMemories: memories)

        indexer.loseIndex()
        let check = await makeSynchronizer(indexer: indexer, state: state).verify(allMemories: memories)

        #expect(indexer.indexedIDs == Set(memories.map(\.id)))
        #expect(check == SpotlightCheck(expected: 2, repaired: 2, removed: 0))
    }

    @Test("The launch check reindexes only what is missing or out of date, and removes strays")
    func repairsOnlyTheDifference() async {
        let indexer = SpotlightIndexerSpy()
        let state = InMemorySpotlightSyncStateStore()
        let kept = makeMemory(keyword: "kept")
        var edited = makeMemory(keyword: "edited", value: "old")
        let stray = makeMemory(keyword: "stray")
        await makeSynchronizer(indexer: indexer, state: state).resume(allMemories: [kept, edited, stray])

        // Edited, and the stray deleted, while Spotlight was not told.
        edited.value = "new"
        let before = indexer.operations.count
        await makeSynchronizer(indexer: indexer, state: state).resume(allMemories: [kept, edited])

        #expect(Array(indexer.operations.dropFirst(before)) == [.remove([stray.id]), .index([edited.id])])
        #expect(indexer.attributes(of: edited.id)?.displayName == "new · edited")
    }

    @Test("An expired memory is not expected in Spotlight, which dropped it by itself")
    func expiredIsNotMissing() async {
        let indexer = SpotlightIndexerSpy()
        let state = InMemorySpotlightSyncStateStore(
            SpotlightSyncState(indexFormatVersion: SpotlightSynchronizer.currentIndexFormatVersion)
        )
        var expired = makeMemory(keyword: "parking")
        expired.expiresAt = Date(timeIntervalSince1970: 10)

        let check = await makeSynchronizer(indexer: indexer, state: state).verify(allMemories: [expired])

        #expect(indexer.operations.isEmpty)
        #expect(check == SpotlightCheck(expected: 0, repaired: 0, removed: 0))
    }

    @Test("If Spotlight cannot be read back, nothing is touched")
    func unreadableIndexChangesNothing() async {
        let indexer = SpotlightIndexerSpy()
        indexer.failReadingBack()
        let state = InMemorySpotlightSyncStateStore()

        let check = await makeSynchronizer(indexer: indexer, state: state).verify(allMemories: [makeMemory()])

        #expect(check == nil)
        #expect(indexer.operations.isEmpty)
    }

    @Test("Changing the options rebuilds the index once")
    func optionsChangeReindexes() async {
        let indexer = SpotlightIndexerSpy()
        let state = InMemorySpotlightSyncStateStore()
        let memory = makeMemory()
        await makeSynchronizer(indexer: indexer, state: state).resume(allMemories: [memory])

        let noIcons = SpotlightOptions(showsCategoryIcon: false)
        let changed = SpotlightSynchronizer(indexer: indexer, stateStore: state, options: { noIcons })
        await changed.resume(allMemories: [memory])
        #expect(indexer.operations.suffix(2) == [.removeAll, .index([memory.id])])

        let count = indexer.operations.count
        await SpotlightSynchronizer(indexer: indexer, stateStore: state, options: { noIcons }).resume(allMemories: [memory])
        #expect(indexer.operations.count == count)
    }

    @Test("Using a memory tells Spotlight when, and how much, it is used")
    func usageReachesSpotlight() async throws {
        let indexer = SpotlightIndexerSpy()
        let state = InMemorySpotlightSyncStateStore()
        let memory = makeMemory()
        let used = Date(timeIntervalSince1970: 9_000)
        let synchronizer = SpotlightSynchronizer(indexer: indexer, stateStore: state, options: { .shipping }, now: { used })

        await synchronizer.recordUse(of: memory)
        await synchronizer.recordUse(of: memory)
        await synchronizer.recordUse(of: memory)

        #expect(indexer.attributes(of: memory.id)?.lastUsedDate == used)
        #expect(indexer.attributes(of: memory.id)?.rankingHint == 40)
        #expect(try state.load().usage[memory.id]?.count == 3)

        // A later full reindex keeps it.
        await synchronizer.reindexAll([memory])
        #expect(indexer.attributes(of: memory.id)?.rankingHint == 40)
    }

    @Test("Usage of a memory that is gone is forgotten at the next check")
    func usageIsPruned() async throws {
        let indexer = SpotlightIndexerSpy()
        let state = InMemorySpotlightSyncStateStore()
        let memory = makeMemory()
        let synchronizer = makeSynchronizer(indexer: indexer, state: state)
        await synchronizer.recordUse(of: memory)

        await synchronizer.verify(allMemories: [])

        #expect(try state.load().usage.isEmpty)
    }

    @Test("Older state files, from before usage and options, still load")
    func decodesOlderState() throws {
        let data = Data(#"{"indexFormatVersion":9,"pendingIndex":[],"pendingDelete":[]}"#.utf8)
        let state = try JSONDecoder().decode(SpotlightSyncState.self, from: data)

        #expect(state.indexFormatVersion == 9)
        #expect(state.usage.isEmpty)
        #expect(state.indexedOptions == nil)
    }
}
