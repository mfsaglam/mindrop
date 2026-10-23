import CloudKit
import Foundation
import os

/// Keeps memories the same on every device signed in to the same iCloud account, through
/// the private database and `CKSyncEngine`.
///
/// The local file stays the source of truth: the app works the same offline, and this
/// sends what changed and takes in what other devices changed. The engine handles
/// retries, push notifications and batching; this decides what a change is and how two
/// versions of a memory become one (`Memory.merged`).
///
/// Only the app runs it. The share extension saves locally, and its memory is sent the
/// next time the app runs. Not on the Apple Watch, which only adds memories
/// (`CloudRecordUpload`) and runs as far back as watchOS 9.
@available(watchOS 10.0, *)
@MainActor
public final class CloudSync {
    nonisolated public static let containerIdentifier = CloudRecord.containerIdentifier

    private let repository: MemoryRepository
    private let stateStore: CloudSyncStateStore
    private let containerIdentifier: String
    private var state: CloudSyncState
    private var engine: CKSyncEngine?
    private let log = Logger(subsystem: "mfsaglam.Mindrop", category: "icloud")

    public init(repository: MemoryRepository, stateStore: CloudSyncStateStore, containerIdentifier: String = containerIdentifier) {
        self.repository = repository
        self.stateStore = stateStore
        self.containerIdentifier = containerIdentifier
        self.state = (try? stateStore.load()) ?? CloudSyncState()
    }

    public static func live(repository: MemoryRepository) throws -> CloudSync {
        CloudSync(repository: repository, stateStore: try FileCloudSyncStateStore.shared())
    }

    public var isRunning: Bool { engine != nil }

    /// Starts syncing: sends whatever changed since the last time and fetches what other
    /// devices changed. Without an iCloud account the engine waits for one.
    public func start() {
        guard engine == nil else { return }
        let configuration = CKSyncEngine.Configuration(
            database: CKContainer(identifier: containerIdentifier).privateCloudDatabase,
            stateSerialization: state.engineState,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if state.engineState == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecord.zoneID))])
        }
        sendLocalChanges()
    }

    /// Stops syncing. Nothing is deleted, here or in iCloud: turning it back on sends what
    /// changed in the meantime.
    public func stop() {
        guard let engine else { return }
        self.engine = nil
        Task { await engine.cancelOperations() }
    }

    /// Queues every memory that changed since iCloud last saw it, and every memory deleted
    /// for good here. Cheap: call it after any change and on returning to the foreground.
    public func sendLocalChanges() {
        guard let engine else { return }
        let pending = state.pendingChanges(for: repository.memories)
        let changes: [CKSyncEngine.PendingRecordZoneChange] =
            pending.saves.map { .saveRecord(CloudRecord.recordID(for: $0)) }
            + pending.deletes.map { .deleteRecord(CloudRecord.recordID(for: $0)) }
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    /// Asks iCloud for changes now, rather than waiting for a push. For returning to the
    /// foreground.
    public func fetchChanges() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
        } catch {
            // The engine retries by itself; nothing to tell the user.
            log.error("Fetching changes failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Events

    private func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let update):
            mutateState { $0.engineState = update.stateSerialization }

        case .accountChange(let change):
            switch change.changeType {
            case .signIn, .switchAccounts:
                // A new account starts empty: everything here is sent to it.
                mutateState { $0.forgetServer() }
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecord.zoneID))])
                sendLocalChanges()
            case .signOut:
                // The memories stay on this device; only what iCloud had is forgotten.
                mutateState { $0.forgetServer() }
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            // The zone was deleted, for example from iCloud settings, or its encryption
            // keys were reset. The memories on this device are sent again.
            if changes.deletions.contains(where: { $0.zoneID == CloudRecord.zoneID }) {
                mutateState { $0.forgetServer() }
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecord.zoneID))])
                sendLocalChanges()
            }

        case .fetchedRecordZoneChanges(let changes):
            take(
                records: changes.modifications.map(\.record),
                deletedIDs: changes.deletions.compactMap { CloudRecord.memoryID(of: $0.recordID) }
            )
            sendLocalChanges()

        case .sentRecordZoneChanges(let sent):
            handleSent(sent)
            sendLocalChanges()

        default:
            break
        }
    }

    /// Merges records from iCloud into the local memories. A memory whose merged version is
    /// exactly what iCloud has is in step; one that kept something of its own stays pending
    /// and is sent back.
    private func take(records: [CKRecord], deletedIDs: [UUID]) {
        let incoming = records.compactMap { record in CloudRecord.memory(from: record).map { (record, $0) } }
        guard !incoming.isEmpty || !deletedIDs.isEmpty else { return }
        let applied: [UUID: Memory]
        do {
            applied = try repository.applyRemote(incoming.map(\.1), deletedIDs: deletedIDs)
        } catch {
            // Left as it is: the engine has already moved past these changes, but the next
            // change to the same memory, here or there, brings them in step again.
            log.error("Could not store \(incoming.count, privacy: .public) change(s) from iCloud")
            return
        }
        mutateState { state in
            for (record, memory) in incoming {
                state.systemFields[memory.id] = CloudRecord.systemFields(of: record)
                if applied[memory.id] == memory { state.known[memory.id] = memory.modifiedAt }
            }
            for id in deletedIDs {
                state.known[id] = nil
                state.systemFields[id] = nil
            }
        }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        mutateState { state in
            for record in sent.savedRecords {
                guard let id = CloudRecord.memoryID(of: record.recordID) else { continue }
                state.systemFields[id] = CloudRecord.systemFields(of: record)
                state.known[id] = record["modifiedAt"] as? Date
            }
            for recordID in sent.deletedRecordIDs {
                guard let id = CloudRecord.memoryID(of: recordID) else { continue }
                state.known[id] = nil
                state.systemFields[id] = nil
            }
            // Already gone from iCloud, which is what was wanted.
            for (recordID, error) in sent.failedRecordDeletes where error.code == .unknownItem {
                guard let id = CloudRecord.memoryID(of: recordID) else { continue }
                state.known[id] = nil
                state.systemFields[id] = nil
            }
        }

        for failure in sent.failedRecordSaves {
            let recordID = failure.record.recordID
            guard let id = CloudRecord.memoryID(of: recordID) else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                // Another device saved first. Merge with its version; whatever this device
                // keeps of its own stays pending and is sent on top of the server's record.
                if let serverRecord = failure.error.serverRecord {
                    take(records: [serverRecord], deletedIDs: [])
                }
            case .zoneNotFound:
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecord.zoneID))])
                mutateState { $0.systemFields[id] = nil }
                engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            case .unknownItem:
                // Deleted from iCloud in the meantime. Kept: an edit here outweighs a
                // deletion elsewhere, and is saved as a new record.
                mutateState { $0.systemFields[id] = nil }
                engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            default:
                // Network trouble, rate limits and the like are retried by the engine.
                log.error("Saving to iCloud failed: \(failure.error.code.rawValue, privacy: .public)")
            }
        }
    }

    /// The record to send for a pending save, or nil if the memory is gone, in which case
    /// the save is dropped.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let id = CloudRecord.memoryID(of: recordID), let memory = repository.memory(id: id) else {
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
        let record = state.systemFields[id].flatMap(CloudRecord.record(fromSystemFields:))
            ?? CKRecord(recordType: CloudRecord.recordType, recordID: recordID)
        CloudRecord.fill(record, from: memory)
        return record
    }

    private func mutateState(_ change: (inout CloudSyncState) -> Void) {
        change(&state)
        do {
            try stateStore.save(state)
        } catch {
            log.error("Could not persist iCloud sync state")
        }
    }
}

@available(watchOS 10.0, *)
extension CloudSync: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // An engine stopped by `stop` may still deliver what it was doing.
        guard syncEngine === engine else { return }
        handle(event)
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await self.record(for: recordID)
        }
    }
}
