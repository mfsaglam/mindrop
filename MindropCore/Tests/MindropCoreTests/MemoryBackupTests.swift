import Foundation
import Testing
@testable import MindropCore

@Suite("Memory backup")
@MainActor
struct MemoryBackupTests {
    @Test("The backup cache keeps summaries and cursor together for one iCloud account")
    func backupCatalogRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cloud-backups-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = CoordinatedFile(url: url)
        let old = MemoryBackup(id: UUID(), createdAt: Date(timeIntervalSince1970: 12.1), memoryCount: 1)
        let new = MemoryBackup(id: UUID(), createdAt: Date(timeIntervalSince1970: 12.2), memoryCount: 2)
        var catalog = CloudBackupCatalog(accountID: "first-account")
        catalog.apply(updates: [old, new], deletions: [])
        catalog.changeToken = Data([1, 2, 3])

        try catalog.save(to: file)

        let restored = try #require(CloudBackupCatalog.load(from: file, for: "first-account"))
        #expect(restored == catalog)
        #expect(restored.orderedBackups == [new, old])
        #expect(CloudBackupCatalog.load(from: file, for: "second-account") == nil)
    }

    @Test("A backup change page updates the saved list without dropping unchanged summaries")
    func backupCatalogAppliesChanges() {
        let unchanged = MemoryBackup(id: UUID(), createdAt: Date(timeIntervalSince1970: 1), memoryCount: 1)
        let deleted = MemoryBackup(id: UUID(), createdAt: Date(timeIntervalSince1970: 2), memoryCount: 2)
        let added = MemoryBackup(id: UUID(), createdAt: Date(timeIntervalSince1970: 3), memoryCount: 3)
        var catalog = CloudBackupCatalog(accountID: "account")
        catalog.apply(updates: [unchanged, deleted], deletions: [])
        catalog.apply(updates: [added], deletions: [deleted.id])
        catalog.apply(updates: [added], deletions: [deleted.id])

        #expect(catalog.orderedBackups == [added, unchanged])
    }

    @Test("Only active memories go into the backup, including recent saves on disk")
    func snapshotContainsActiveMemories() throws {
        let (repository, store, _) = try makeRepository()
        let active = makeMemory(keyword: "home wifi")
        var expired = makeMemory(keyword: "hotel code")
        expired.expiresAt = Date(timeIntervalSince1970: 500)
        var deleted = makeMemory(keyword: "door code")
        deleted.deletedAt = Date(timeIntervalSince1970: 500)
        try store.save([active, expired, deleted])

        #expect(try repository.memoriesForBackup() == [active])
    }

    @Test("Restore keeps the current version, protects sensitive values and is safe to repeat")
    func restoreCopies() async throws {
        let older = makeMemory(keyword: "home wifi", value: "Old")
        let unchanged = makeMemory(keyword: "office wifi")
        let missing = makeMemory(keyword: "router model")
        var expired = makeMemory(keyword: "hotel code")
        expired.expiresAt = Date(timeIntervalSince1970: 500)
        var current = older
        current.value = "New"
        current.isSensitive = true
        let (repository, store, indexer) = try makeRepository(memories: [current, unchanged])
        let snapshot = [older, unchanged, missing, expired]
        let backup = MemoryBackup(id: UUID(), createdAt: .now, memoryCount: snapshot.count)
        var reports = 0
        repository.onLocalChange = { reports += 1 }

        #expect(try repository.restore(snapshot, from: backup) == 2)
        #expect(try repository.restore(snapshot, from: backup) == 0)
        #expect(reports == 1)
        #expect(repository.memory(id: current.id) == current)
        let previous = try #require(repository.memory(id: backup.restoredID(for: older.id)))
        #expect(previous.value == older.value)
        #expect(previous.isSensitive)
        #expect(repository.memory(id: backup.restoredID(for: missing.id))?.value == missing.value)
        #expect(try store.load().count == 4)
        await repository.indexingTask?.value
        #expect(indexer.attributes(of: previous.id)?.displayName.contains(older.value) == false)
    }

    @Test("A failed restore changes neither the library nor sync state")
    func restoreFailure() throws {
        let (repository, store, _) = try makeRepository()
        let memory = makeMemory()
        let backup = MemoryBackup(id: UUID(), createdAt: .now, memoryCount: 1)
        struct WriteFailure: Error {}
        store.saveError = WriteFailure()
        repository.onLocalChange = { Issue.record("Failed restore notified iCloud") }

        #expect(throws: WriteFailure.self) {
            try repository.restore([memory], from: backup)
        }
        #expect(repository.memories.isEmpty)
        #expect(try store.load().isEmpty)
    }
}
