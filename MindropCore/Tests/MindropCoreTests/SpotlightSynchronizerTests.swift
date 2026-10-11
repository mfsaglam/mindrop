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
        SpotlightSynchronizer(indexer: indexer, stateStore: state)
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
}
