import CryptoKit
import Foundation
import Testing
@testable import MindropCore

@Suite("iCloud Drive backup")
struct DriveMemoryBackupTests {
    @Test("The encrypted file restores its original backup identity and memories")
    func roundTrip() throws {
        var memory = makeMemory(keyword: "private wifi", value: "secret-example")
        memory.isSensitive = true
        let key = SymmetricKey(size: .bits256)
        let keyID = UUID()
        let backupID = UUID()
        let date = Date(timeIntervalSince1970: 2_000)
        let snapshot = try DriveBackupCodec.encodeMemories([memory])
        let file = try DriveBackupCodec.seal(snapshot, id: backupID, createdAt: date, keyID: keyID, key: key)
        #expect(!String(decoding: file, as: UTF8.self).contains(memory.value))

        let (backup, memories) = try DriveBackupCodec.open(file) { id in
            #expect(id == keyID)
            return key
        }
        #expect(backup.id == backupID)
        #expect(backup.createdAt == date)
        #expect(backup.memoryCount == 1)
        #expect(memories == [memory])

        #expect(throws: (any Error).self) {
            try DriveBackupCodec.open(file) { _ in SymmetricKey(size: .bits256) }
        }
    }

    @Test("Reordering a library keeps its fingerprint input stable and content changes update it")
    func stablePayload() throws {
        let first = makeMemory(keyword: "first item")
        var second = makeMemory(keyword: "second item")
        let original = try DriveBackupCodec.encodeMemories([first, second])
        #expect(try DriveBackupCodec.encodeMemories([second, first]) == original)
        second.isSensitive = true
        #expect(try DriveBackupCodec.encodeMemories([first, second]) != original)
    }

    @Test("An automatic backup is due at most once per 24 hours")
    func automaticInterval() {
        let last = Date(timeIntervalSince1970: 1_000)
        #expect(DriveBackupPolicy.isDue(lastAutomaticAt: nil, now: last))
        #expect(!DriveBackupPolicy.isDue(lastAutomaticAt: last, now: last.addingTimeInterval(86_399)))
        #expect(DriveBackupPolicy.isDue(lastAutomaticAt: last, now: last.addingTimeInterval(86_400)))
    }
}
