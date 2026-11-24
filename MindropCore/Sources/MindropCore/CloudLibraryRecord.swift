import CloudKit
import Foundation

/// Library metadata is stored in the existing private zone under prefixed IDs.
/// Older apps only recognize bare memory UUIDs and leave these records alone.
enum CloudLibraryRecord {
    static let recordType = "LibraryMetadata"
    private static let payloadField = "payload"

    struct ID: Codable, Hashable, Sendable {
        let kind: LibraryRecord.Kind
        let uuid: UUID

        var cloudID: CKRecord.ID {
            CKRecord.ID(recordName: "\(kind.rawValue)-\(uuid.uuidString)", zoneID: CloudRecord.zoneID)
        }

        init(kind: LibraryRecord.Kind, uuid: UUID) {
            self.kind = kind
            self.uuid = uuid
        }

        init?(_ id: CKRecord.ID) {
            guard id.zoneID == CloudRecord.zoneID else { return nil }
            let parts = id.recordName.split(separator: "-", maxSplits: 1)
            guard parts.count == 2,
                  let kind = LibraryRecord.Kind(rawValue: String(parts[0])),
                  let uuid = UUID(uuidString: String(parts[1])) else { return nil }
            self.init(kind: kind, uuid: uuid)
        }
    }

    static func fill(_ record: CKRecord, from value: LibraryRecord) throws {
        let payload = try JSONEncoder.mindrop.encode(value)
        record.encryptedValues[payloadField] = String(decoding: payload, as: UTF8.self)
    }

    static func read(_ record: CKRecord) -> (ID, LibraryRecord)? {
        guard record.recordType == recordType, let id = ID(record.recordID),
              let payload = record.encryptedValues[payloadField] as? String,
              let value = try? JSONDecoder.mindrop.decode(LibraryRecord.self, from: Data(payload.utf8)),
              id.kind == value.kind else { return nil }
        return (id, value)
    }
}
