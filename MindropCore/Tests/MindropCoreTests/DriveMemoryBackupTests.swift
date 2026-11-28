import CryptoKit
import Foundation
import Testing
@testable import MindropCore

@Suite("iCloud Drive backup")
struct DriveMemoryBackupTests {
    @Test("The encrypted file restores its identity, memories and folders")
    func roundTrip() throws {
        var memory = makeMemory(keyword: "private wifi", value: "secret-example")
        memory.isSensitive = true
        let key = SymmetricKey(size: .bits256)
        let keyID = UUID()
        let backupID = UUID()
        let date = Date(timeIntervalSince1970: 2_000)
        let folder = DriveBackupLibrary.Folder(id: UUID(), name: "Home", memoryIDs: [memory.id])
        let library = DriveBackupLibrary(memories: [memory], folders: [folder])
        let file = try DriveBackupCodec.seal(library, id: backupID, createdAt: date, keyID: keyID, key: key)
        #expect(!String(decoding: file, as: UTF8.self).contains(memory.value))

        let backup = try DriveBackupCodec.open(file) { id in
            #expect(id == keyID)
            return key
        }
        #expect(backup.id == backupID)
        #expect(backup.createdAt == date)
        #expect(backup.library.memories == [memory])
        let restoredFolder = try #require(backup.library.folders.first)
        #expect(restoredFolder.id == folder.id)
        #expect(restoredFolder.name == folder.name)
        #expect(restoredFolder.memoryIDs == [memory.id])

        #expect(throws: (any Error).self) {
            try DriveBackupCodec.open(file) { _ in SymmetricKey(size: .bits256) }
        }
    }

    @Test("Version 1 files remain readable after updating the app")
    func legacyFile() throws {
        struct Header: Encodable {
            let version = 1
            let keyID: UUID
        }
        struct Envelope: Encodable {
            let header: Header
            let sealed: Data
        }
        struct Snapshot: Encodable {
            let id: UUID
            let createdAt: Date
            let memories: Data
        }
        let encoder = JSONEncoder()
        let key = SymmetricKey(size: .bits256)
        let keyID = UUID()
        let memory = makeMemory()
        let snapshot = Snapshot(id: UUID(), createdAt: .now, memories: try encoder.encode([memory]))
        let sealed = try AES.GCM.seal(
            encoder.encode(snapshot),
            using: key,
            authenticating: Data("Mindrop backup 1 \(keyID.uuidString)".utf8)
        )
        let file = try encoder.encode(Envelope(header: Header(keyID: keyID), sealed: #require(sealed.combined)))

        let restored = try DriveBackupCodec.open(file) { _ in key }

        #expect(restored.id == snapshot.id)
        #expect(restored.library.memories == [memory])
        #expect(restored.library.folders.isEmpty)
    }

    @Test("Only changes to memories or folder organization affect the fingerprint")
    func stablePayload() throws {
        let first = makeMemory(keyword: "first item")
        var second = makeMemory(keyword: "second item")
        let folderID = UUID()
        func payload(_ memories: [Memory], in order: [UUID], folderName: String = "Home") throws -> Data {
            try DriveBackupCodec.encodeLibrary(DriveBackupLibrary(
                memories: memories, folders: [.init(id: folderID, name: folderName, memoryIDs: order)]
            ))
        }
        let original = try payload([first, second], in: [first.id, second.id])
        #expect(try payload([second, first], in: [second.id, first.id]) == original)
        #expect(try payload([first, second], in: [first.id]) != original)
        #expect(try payload([first, second], in: [first.id, second.id], folderName: "Travel") != original)
        second.isSensitive = true
        #expect(try payload([first, second], in: [first.id, second.id]) != original)
    }

    @Test("Discovery orders and deduplicates only files managed in the backup directory")
    func managedFiles() {
        let directory = URL(filePath: "/container/Documents/Backups")
        let other = URL(filePath: "/container/Documents/Other")
        let older = directory.appending(path: "Mindrop-2026-05-01-000000Z-\(UUID()).mindropbackup")
        let newer = directory.appending(path: "Mindrop-2026-05-02-000000Z-\(UUID()).mindropbackup")
        let otherBackup = other.appending(path: newer.lastPathComponent)
        let personalFile = directory.appending(path: "My-archive.mindropbackup")

        #expect(DriveBackupPolicy.managedFiles([older, otherBackup, newer, personalFile, older], in: directory) == [newer, older])
    }

    @Test("An automatic backup is due at most once per 24 hours")
    func automaticInterval() {
        let last = Date(timeIntervalSince1970: 1_000)
        #expect(DriveBackupPolicy.isDue(lastAutomaticAt: nil, now: last))
        #expect(!DriveBackupPolicy.isDue(lastAutomaticAt: last, now: last.addingTimeInterval(86_399)))
        #expect(DriveBackupPolicy.isDue(lastAutomaticAt: last, now: last.addingTimeInterval(86_400)))
    }

    @Test("First-install recovery keeps IDs and empty folders and skips expired memories")
    @MainActor
    func recoverLibrary() throws {
        let active = makeMemory()
        var expired = makeMemory()
        expired.expiresAt = Date(timeIntervalSince1970: 500)
        let (source, _, _) = try makeRepository(memories: [active, expired])
        try source.folders.add(named: "Home")
        try source.folders.add(named: "Travel")
        let home = try #require(source.folders.custom.first)
        try source.move(active, to: home.id)
        try source.move(expired, to: home.id)
        let library = try source.driveBackupLibrary()
        let (target, store, _) = try makeRepository()
        let snapshot = DriveBackupSnapshot(id: UUID(), createdAt: .now, library: library)

        try target.recoverDriveBackup(snapshot)
        try target.recoverDriveBackup(snapshot)

        #expect(try store.load() == [active])
        #expect(target.folders.custom.map(\.name) == ["Home", "Travel"])
        #expect(target.folders.folderID(for: active.id) == home.id)

        let (existing, _, _) = try makeRepository(memories: [makeMemory()])
        try existing.recoverDriveBackup(snapshot)
        #expect(existing.memory(id: active.id) == nil)
        #expect(existing.folders.custom.isEmpty)
    }

    @Test("Manual recovery places restored copies in folders without moving the current memories")
    @MainActor
    func restoreCopiesIntoFolders() throws {
        let previous = makeMemory(value: "Old")
        var current = previous
        current.value = "New"
        let (repository, _, _) = try makeRepository(memories: [current])
        let homeID = UUID()
        let snapshot = DriveBackupSnapshot(id: UUID(), createdAt: .now, library: DriveBackupLibrary(
            memories: [previous], folders: [.init(id: homeID, name: "Home", memoryIDs: [previous.id])]
        ))

        #expect(try repository.restoreDriveBackup(snapshot) == 1)
        #expect(try repository.restoreDriveBackup(snapshot) == 0)
        #expect(repository.results(for: "", folderID: homeID).map(\.value) == ["Old"])
        #expect(repository.results(for: "", folderID: MemoryFolders.generalID).map(\.value) == ["New"])
    }

    @Test("Manually restoring a missing memory preserves the ID used by iCloud Sync")
    @MainActor
    func manualRestoreThenSync() throws {
        let memory = makeMemory()
        let snapshot = DriveBackupSnapshot(id: UUID(), createdAt: .now, library: DriveBackupLibrary(
            memories: [memory], folders: []
        ))
        let (repository, _, _) = try makeRepository()

        #expect(try repository.restoreDriveBackup(snapshot) == 1)
        var synced = memory
        synced.category = CategoryAssignment(category: .network, source: .automatic)
        synced.modifiedAt = memory.modifiedAt.addingTimeInterval(10)
        try repository.applyRemote([synced], deletedIDs: [])

        #expect(try repository.restoreDriveBackup(snapshot) == 0)
        #expect(repository.memories == [synced])
    }

    @Test("Repeating a legacy manual restore does not add an original alongside its legacy copy")
    @MainActor
    func repeatLegacyManualRestore() throws {
        let memory = makeMemory()
        let backup = MemoryBackup(id: UUID(), createdAt: .now, memoryCount: 1)
        let snapshot = DriveBackupSnapshot(id: backup.id, createdAt: backup.createdAt, library: .init(
            memories: [memory], folders: []
        ))
        let (repository, _, _) = try makeRepository()
        #expect(try repository.restore([memory], from: backup) == 1)

        #expect(try repository.restoreDriveBackup(snapshot) == 0)
        #expect(repository.memories.map(\.id) == [backup.restoredID(for: memory.id)])
    }

    @Test("Review finds legacy copies in General and moves only the chosen matches to Recently Deleted")
    @MainActor
    func reviewLegacyCopies() throws {
        let filed = makeMemory(keyword: "Home router")
        let general = makeMemory(keyword: "Bus times")
        let differentVersion = makeMemory(keyword: "Old recipe", value: "Version one")
        let stacked = makeMemory(keyword: "Garage code")
        let moved = makeMemory(keyword: "Hotel address")
        let backup = MemoryBackup(id: UUID(), createdAt: .now, memoryCount: 5)
        let (repository, _, _) = try makeRepository()
        #expect(try repository.restore([filed, general, differentVersion, stacked, moved], from: backup) == 5)

        var edited = differentVersion
        edited.value = "Version two"
        try repository.applyRemote([filed, general, edited, stacked, moved], deletedIDs: [])
        try repository.folders.add(named: "Home")
        let home = try #require(repository.folders.custom.first)
        try repository.move(filed, to: home.id)
        try repository.setStackMembership([backup.restoredID(for: stacked.id)], included: true)
        try repository.move(ids: [backup.restoredID(for: moved.id)], to: home.id)

        let matches = repository.backupDuplicates
        #expect(Set(matches.map(\.id)) == Set([backup.restoredID(for: filed.id), backup.restoredID(for: general.id)]))
        let filedCopy = try #require(matches.first { $0.originalID == filed.id })
        #expect(filedCopy.originalFolderID == home.id)
        #expect(try repository.deleteBackupDuplicates([filedCopy]) == 1)
        #expect(repository.deletedMemories.map(\.id) == [filedCopy.id])
        #expect(repository.results(for: "", folderID: home.id).contains(filed))
        #expect(repository.backupDuplicates.map(\.originalID) == [general.id])
        #expect(try repository.deleteBackupDuplicates([filedCopy]) == 0)
    }

    @Test("Review rechecks the match before moving a copy to Recently Deleted")
    @MainActor
    func recheckApprovedCopy() throws {
        let memory = makeMemory()
        let backup = MemoryBackup(id: UUID(), createdAt: .now, memoryCount: 1)
        let (repository, _, _) = try makeRepository()
        try repository.restore([memory], from: backup)
        try repository.applyRemote([memory], deletedIDs: [])
        let approved = try #require(repository.backupDuplicates.first)

        let copy = try #require(repository.memory(id: approved.id))
        try repository.update(copy, keyword: copy.keyword, value: "Changed after review")

        #expect(try repository.deleteBackupDuplicates([approved]) == 0)
        #expect(repository.deletedMemories.isEmpty)
        #expect(repository.memory(id: copy.id)?.value == "Changed after review")
    }
}
