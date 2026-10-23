import Foundation
import Testing
@testable import MindropCore

@Suite("Apple Watch handoff")
@MainActor
struct WatchHandoffTests {
    @Test("A memory saved on the watch reaches the iPhone exactly as it was")
    func memoryRoundTrip() throws {
        let memory = try #require(WatchHandoff.newMemory(keyword: "gym locker", value: "4826", isSensitive: true))
        let received = WatchHandoff.memory(from: try WatchHandoff.userInfo(for: memory))

        #expect(received == memory)
        #expect(received?.isSensitive == true)
        #expect(received?.category == nil)
    }

    @Test("What is typed on the watch is normalised as in the app, and must not be empty")
    func newMemory() throws {
        let memory = try #require(WatchHandoff.newMemory(keyword: "  gym   locker ", value: " 4826\n", isSensitive: false))
        #expect(memory.keyword == "gym locker")
        #expect(memory.value == "4826")

        #expect(WatchHandoff.newMemory(keyword: "  ", value: "4826", isSensitive: false) == nil)
        #expect(WatchHandoff.newMemory(keyword: "gym locker", value: "\n", isSensitive: false) == nil)
    }

    @Test("A transfer that holds no memory is ignored")
    func foreignUserInfo() {
        #expect(WatchHandoff.memory(from: [:]) == nil)
        #expect(WatchHandoff.memory(from: ["memory": Data("not json".utf8)]) == nil)
    }

    @Test("The watch writes to iCloud only once the iPhone says iCloud Sync is on")
    func iCloudPermission() {
        #expect(!WatchHandoff.syncsWithICloud(in: [:]))
        #expect(WatchHandoff.syncsWithICloud(in: WatchHandoff.applicationContext(syncsWithICloud: true)))
        #expect(!WatchHandoff.syncsWithICloud(in: WatchHandoff.applicationContext(syncsWithICloud: false)))
    }

    @Test("A memory from the watch is filed like one from another device, once, however often it arrives")
    func takenInOnce() throws {
        let (repository, _, _) = try makeRepository()
        let memory = try #require(WatchHandoff.newMemory(keyword: "gym locker", value: "4826", isSensitive: false))

        try repository.applyRemote([memory], deletedIDs: [])
        try repository.applyRemote([memory], deletedIDs: [])

        #expect(repository.memories.filter { $0.id == memory.id }.count == 1)
        #expect(repository.memory(id: memory.id)?.value == "4826")
    }
}
