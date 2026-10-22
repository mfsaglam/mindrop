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
    /// The options the index was last fully built with. A change rebuilds it, like a
    /// format version does. Nil before options existed, which counts as `shipping`.
    public var indexedOptions: SpotlightOptions?
    /// How each memory has been used on this device, for Spotlight's ranking. Kept here,
    /// not in the memory: it is this device's habit, and not worth an iCloud change.
    public var usage: [UUID: SpotlightUsage]

    public init(
        indexFormatVersion: Int = 0,
        pendingIndex: Set<UUID> = [],
        pendingDelete: Set<UUID> = [],
        indexedOptions: SpotlightOptions? = nil,
        usage: [UUID: SpotlightUsage] = [:]
    ) {
        self.indexFormatVersion = indexFormatVersion
        self.pendingIndex = pendingIndex
        self.pendingDelete = pendingDelete
        self.indexedOptions = indexedOptions
        self.usage = usage
    }

    /// Written out by hand only so that files saved before a field existed still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        indexFormatVersion = try container.decode(Int.self, forKey: .indexFormatVersion)
        pendingIndex = try container.decode(Set<UUID>.self, forKey: .pendingIndex)
        pendingDelete = try container.decode(Set<UUID>.self, forKey: .pendingDelete)
        indexedOptions = try container.decodeIfPresent(SpotlightOptions.self, forKey: .indexedOptions)
        usage = try container.decodeIfPresent([UUID: SpotlightUsage].self, forKey: .usage) ?? [:]
    }

    public var hasPendingWork: Bool { !pendingIndex.isEmpty || !pendingDelete.isEmpty }
}

/// How often and how lately a memory was opened or copied on this device.
public struct SpotlightUsage: Codable, Equatable, Sendable {
    public var lastUsedAt: Date
    public var count: Int

    public init(lastUsedAt: Date, count: Int) {
        self.lastUsedAt = lastUsedAt
        self.count = count
    }

    /// 0 to 100, as Spotlight expects, rising quickly at first and slowly after:
    /// 1 use is 20, 3 are 40, 7 are 60, 31 or more are 100.
    public var rankingHint: Int {
        min(100, Int((20 * log2(Double(count + 1))).rounded()))
    }
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
