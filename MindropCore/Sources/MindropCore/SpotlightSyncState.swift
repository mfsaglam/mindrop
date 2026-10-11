import Foundation

/// What Mindrop remembers about the state of its Spotlight index between launches.
///
/// This is what keeps indexing recoverable without reindexing everything on every
/// launch: only work that is known to have failed is retried.
public struct SpotlightSyncState: Codable, Equatable, Sendable {
    /// Bumped in code when the indexed metadata changes shape, which triggers one
    /// full reindex on the next launch and never again.
    public var indexFormatVersion: Int
    public var pendingIndex: Set<UUID>
    public var pendingDelete: Set<UUID>

    public init(indexFormatVersion: Int = 0, pendingIndex: Set<UUID> = [], pendingDelete: Set<UUID> = []) {
        self.indexFormatVersion = indexFormatVersion
        self.pendingIndex = pendingIndex
        self.pendingDelete = pendingDelete
    }

    public var hasPendingWork: Bool { !pendingIndex.isEmpty || !pendingDelete.isEmpty }
}

public protocol SpotlightSyncStateStore: Sendable {
    func load() throws -> SpotlightSyncState
    func save(_ state: SpotlightSyncState) throws
}

public struct FileSpotlightSyncStateStore: SpotlightSyncStateStore {
    private let file: CoordinatedFile

    public init(url: URL) {
        self.file = CoordinatedFile(url: url)
    }

    public static func shared() throws -> FileSpotlightSyncStateStore {
        guard let container = AppGroup.containerURL else { throw MemoryStoreError.appGroupUnavailable }
        return FileSpotlightSyncStateStore(url: container.appending(path: AppGroup.syncStateFileName))
    }

    public func load() throws -> SpotlightSyncState {
        guard let data = try file.read(), !data.isEmpty else { return SpotlightSyncState() }
        return try JSONDecoder.mindrop.decode(SpotlightSyncState.self, from: data)
    }

    public func save(_ state: SpotlightSyncState) throws {
        try file.write(try JSONEncoder.mindrop.encode(state))
    }
}

public final class InMemorySpotlightSyncStateStore: SpotlightSyncStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: SpotlightSyncState

    public init(_ state: SpotlightSyncState = SpotlightSyncState()) {
        self.state = state
    }

    public func load() throws -> SpotlightSyncState { lock.withLock { state } }
    public func save(_ state: SpotlightSyncState) throws { lock.withLock { self.state = state } }
}
