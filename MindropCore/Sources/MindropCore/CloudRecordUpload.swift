import CloudKit
import Foundation

/// Saves one new memory straight into the private iCloud database, for a device that adds
/// memories but does not keep the whole library in sync: the Apple Watch. The record is the
/// same as the iPhone's (`CloudRecord`), encrypted the same way, so the iPhone's sync engine
/// takes it in as a change from another device, then files it, indexes it and categorises it.
public enum CloudRecordUpload {
    public enum Outcome: Equatable, Sendable {
        /// iCloud has it.
        case saved
        /// Not now, but maybe later: no network, iCloud busy.
        case retryLater
        /// Not through iCloud: no account, or the iPhone has never synced, so the zone does
        /// not exist yet. The iPhone gets the memory another way.
        case unavailable
    }

    public static func save(
        _ memory: Memory,
        containerIdentifier: String = CloudRecord.containerIdentifier
    ) async -> Outcome {
        let container = CKContainer(identifier: containerIdentifier)
        guard (try? await container.accountStatus()) == .available else { return .unavailable }

        let record = CKRecord(recordType: CloudRecord.recordType, recordID: CloudRecord.recordID(for: memory.id))
        CloudRecord.fill(record, from: memory)
        do {
            let (results, _) = try await container.privateCloudDatabase.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged
            )
            switch results[record.recordID] {
            case .success: return .saved
            case .failure(let error): return outcome(of: error)
            case nil: return .retryLater
            }
        } catch {
            return outcome(of: error)
        }
    }

    private static func outcome(of error: Error) -> Outcome {
        switch (error as? CKError)?.code {
        // Already saved, by an earlier try whose answer was lost.
        case .serverRecordChanged:
            return .saved
        case .zoneNotFound, .userDeletedZone, .notAuthenticated, .permissionFailure, .badContainer, .missingEntitlement:
            return .unavailable
        default:
            return .retryLater
        }
    }
}
