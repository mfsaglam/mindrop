import CloudKit
import Foundation

/// What Mindrop remembers between launches about its iCloud sync.
///
/// Changes are found by comparison rather than recorded as they happen, so a memory the
/// share extension saved, or one changed while sync was off, is still sent: anything
/// whose `modifiedAt` differs from what the server last agreed to is pending.
@available(watchOS 10.0, *)
public struct CloudSyncState: Codable, Sendable {
    /// The sync engine's own progress: what it has fetched, what it still has to send.
    public var engineState: CKSyncEngine.State.Serialization?
    /// Each memory's `modifiedAt` as last sent to or received from iCloud.
    public var known: [UUID: Date] = [:]
    /// Each record's system fields, so a save updates the server's version.
    public var systemFields: [UUID: Data] = [:]

    public init() {}

    /// Memories to send, and ids to delete from iCloud because they were deleted for
    /// good here.
    func pendingChanges(for memories: [Memory]) -> (saves: [UUID], deletes: [UUID]) {
        let saves = memories
            .filter { memory in known[memory.id].map { !Self.isSameInstant($0, memory.modifiedAt) } ?? true }
            .map(\.id)
        let present = Set(memories.map(\.id))
        let deletes = known.keys.filter { !present.contains($0) }
        return (saves, deletes)
    }

    /// CloudKit keeps dates to the millisecond, so a date that went there and back may
    /// differ from the original by less than that.
    static func isSameInstant(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 0.001
    }

    /// Forgets what any iCloud account had, after a sign-out, a switch of accounts, or
    /// the zone being deleted. The engine's own state is reset by the engine.
    mutating func forgetServer() {
        known = [:]
        systemFields = [:]
    }
}

@available(watchOS 10.0, *)
public protocol CloudSyncStateStore: Sendable {
    func load() throws -> CloudSyncState
    func save(_ state: CloudSyncState) throws
}

@available(watchOS 10.0, *)
public struct FileCloudSyncStateStore: CloudSyncStateStore {
    private let file: CoordinatedFile

    public init(url: URL) {
        self.file = CoordinatedFile(url: url)
    }

    public static func shared() throws -> FileCloudSyncStateStore {
        guard let container = AppGroup.containerURL else { throw MemoryStoreError.appGroupUnavailable }
        return FileCloudSyncStateStore(url: container.appending(path: AppGroup.cloudSyncStateFileName))
    }

    public func load() throws -> CloudSyncState {
        guard let data = try file.read(), !data.isEmpty else { return CloudSyncState() }
        return try JSONDecoder.mindrop.decode(CloudSyncState.self, from: data)
    }

    public func save(_ state: CloudSyncState) throws {
        try file.write(try JSONEncoder.mindrop.encode(state))
    }
}
