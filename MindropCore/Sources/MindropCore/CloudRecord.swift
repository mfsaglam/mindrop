import CloudKit
import Foundation

/// How a memory is stored in the user's private iCloud database: one record per memory,
/// in one zone, named by the memory's UUID.
///
/// The keyword, the value and the category are encrypted fields: end-to-end encrypted
/// with keys in the user's iCloud Keychain, so not even Apple can read them. Dates and
/// flags are plain, since they say nothing on their own.
public enum CloudRecord {
    static let recordType = "Memory"
    public static let zoneID = CKRecordZone.ID(zoneName: "Memories")

    static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    static func memoryID(of recordID: CKRecord.ID) -> UUID? {
        UUID(uuidString: recordID.recordName)
    }

    private enum Field {
        static let keyword = "keyword"
        static let value = "value"
        static let category = "category"
        static let categorySource = "categorySource"
        static let categoryVersion = "categoryVersion"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let modifiedAt = "modifiedAt"
        static let expiresAt = "expiresAt"
        static let deletedAt = "deletedAt"
        static let isSensitive = "isSensitive"
    }

    /// Writes every field of the memory into the record, clearing the ones it lacks.
    static func fill(_ record: CKRecord, from memory: Memory) {
        record.encryptedValues[Field.keyword] = memory.keyword
        record.encryptedValues[Field.value] = memory.value
        record.encryptedValues[Field.category] = memory.category?.category.rawValue
        record.encryptedValues[Field.categorySource] = memory.category?.source.rawValue
        record[Field.categoryVersion] = memory.category?.version
        record[Field.createdAt] = memory.createdAt
        record[Field.updatedAt] = memory.updatedAt
        record[Field.modifiedAt] = memory.modifiedAt
        record[Field.expiresAt] = memory.expiresAt
        record[Field.deletedAt] = memory.deletedAt
        record[Field.isSensitive] = memory.isSensitive
    }

    /// Nil for a record that is not a complete memory, such as one written by a newer
    /// version that this one cannot read.
    static func memory(from record: CKRecord) -> Memory? {
        guard record.recordType == recordType,
              let id = memoryID(of: record.recordID),
              let keyword = record.encryptedValues[Field.keyword] as? String,
              let value = record.encryptedValues[Field.value] as? String,
              let createdAt = record[Field.createdAt] as? Date,
              let updatedAt = record[Field.updatedAt] as? Date
        else { return nil }

        var category: CategoryAssignment?
        if let rawCategory = record.encryptedValues[Field.category] as? String,
           let rawSource = record.encryptedValues[Field.categorySource] as? String,
           let memoryCategory = MemoryCategory(rawValue: rawCategory),
           let source = CategoryAssignment.Source(rawValue: rawSource) {
            category = CategoryAssignment(
                category: memoryCategory,
                source: source,
                version: record[Field.categoryVersion] as? Int
            )
        }
        return Memory(
            id: id,
            keyword: keyword,
            value: value,
            createdAt: createdAt,
            updatedAt: updatedAt,
            category: category,
            expiresAt: record[Field.expiresAt] as? Date,
            isSensitive: record[Field.isSensitive] as? Bool ?? false,
            modifiedAt: record[Field.modifiedAt] as? Date ?? updatedAt,
            deletedAt: record[Field.deletedAt] as? Date
        )
    }

    /// The record's identity and change tag, without its contents. Kept per memory so the
    /// next save is an update of the server's version rather than a conflict.
    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
