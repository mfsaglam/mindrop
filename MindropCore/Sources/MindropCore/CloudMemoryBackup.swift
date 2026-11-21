import CloudKit
import CryptoKit
import Foundation

private typealias BackupChangesPage = (
    modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
    deletions: [CKDatabase.RecordZoneChange.Deletion],
    changeToken: CKServerChangeToken,
    moreComing: Bool
)

public struct MemoryBackup: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let memoryCount: Int
}

/// An immutable snapshot in the user's private CloudKit database.
@available(watchOS 10.0, *)
public struct CloudMemoryBackup: Sendable {
    private static let zone = CKRecordZone.ID(zoneName: "MemoryBackups")
    private static let recordType = "MemoryBackup"
    private static let recordPrefix = "backup-"

    private let container = CKContainer(identifier: CloudRecord.containerIdentifier)
    private var database: CKDatabase { container.privateCloudDatabase }

    public init() {}

    public func list() async throws -> [MemoryBackup] {
        var backups: [UUID: MemoryBackup] = [:]
        var token: CKServerChangeToken?
        while true {
            let page: BackupChangesPage
            do {
                page = try await database.recordZoneChanges(
                    inZoneWith: Self.zone,
                    since: token,
                    desiredKeys: ["memoryCount"]
                )
            } catch let error as CKError where error.code == .zoneNotFound {
                return []
            }
            for change in page.modificationResultsByID.values {
                let record = try change.get().record
                if let backup = Self.summary(for: record) { backups[backup.id] = backup }
            }
            for deletion in page.deletions {
                if let id = Self.backupID(for: deletion.recordID) { backups[id] = nil }
            }
            guard page.moreComing else { break }
            token = page.changeToken
        }
        return backups.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func create(memories: [Memory]) async throws -> MemoryBackup {
        guard !memories.isEmpty else { throw MemoryBackupError.empty }

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "memories.json")
        let payload = try JSONEncoder.mindrop.encode(MemoryBackupSnapshot(memories: memories))
        #if os(iOS)
        try payload.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try payload.write(to: file, options: .atomic)
        #endif

        let record = CKRecord(recordType: Self.recordType, recordID: Self.recordID(for: UUID()))
        record["memoryCount"] = memories.count
        // CloudKit encrypts assets by default. The payload contains all record contents.
        record["snapshot"] = CKAsset(fileURL: file)
        let saved: CKRecord
        do {
            saved = try await database.save(record)
        } catch let error as CKError where error.code == .zoneNotFound {
            _ = try await database.save(CKRecordZone(zoneID: Self.zone))
            saved = try await database.save(record)
        }
        guard let backup = Self.summary(for: saved) else { throw MemoryBackupError.invalid }
        return backup
    }

    public func memories(in backup: MemoryBackup) async throws -> [Memory] {
        let record = try await database.record(for: Self.recordID(for: backup.id))
        guard let summary = Self.summary(for: record),
              let asset = record["snapshot"] as? CKAsset,
              let file = asset.fileURL
        else { throw MemoryBackupError.invalid }

        let snapshot = try JSONDecoder.mindrop.decode(MemoryBackupSnapshot.self, from: Data(contentsOf: file))
        guard snapshot.version == 1,
              snapshot.memories.count == summary.memoryCount,
              Set(snapshot.memories.map(\.id)).count == snapshot.memories.count
        else { throw MemoryBackupError.invalid }
        return snapshot.memories
    }

    public func delete(_ backup: MemoryBackup) async throws {
        do {
            _ = try await database.deleteRecord(withID: Self.recordID(for: backup.id))
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // A different device already removed the copy.
        }
    }

    private static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: recordPrefix + id.uuidString, zoneID: zone)
    }

    private static func backupID(for recordID: CKRecord.ID) -> UUID? {
        guard recordID.zoneID == zone, recordID.recordName.hasPrefix(recordPrefix) else { return nil }
        return UUID(uuidString: String(recordID.recordName.dropFirst(recordPrefix.count)))
    }

    private static func summary(for record: CKRecord) -> MemoryBackup? {
        guard record.recordType == recordType,
              let id = backupID(for: record.recordID),
              let createdAt = record.creationDate,
              let memoryCount = record["memoryCount"] as? Int
        else { return nil }
        return MemoryBackup(id: id, createdAt: createdAt, memoryCount: memoryCount)
    }
}

enum MemoryBackupError: Error {
    case empty
    case invalid
}

private struct MemoryBackupSnapshot: Codable {
    var version = 1
    let memories: [Memory]
}

extension MemoryBackup {
    /// Gives every restored copy a stable identity across devices and repeated restores.
    func restoredID(for id: UUID) -> UUID {
        var hash = SHA256()
        hash.update(data: Data(self.id.uuidString.utf8))
        hash.update(data: Data(id.uuidString.utf8))
        let bytes = Array(hash.finalize().prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
