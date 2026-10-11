import Foundation

/// Persistence boundary. The repository only ever talks to this, so tests can run
/// entirely in memory and the storage implementation stays replaceable.
public protocol MemoryStore: Sendable {
    func load() throws -> [Memory]
    func save(_ memories: [Memory]) throws
}

/// JSON file persistence inside the App Group container.
///
/// A single file holds the whole collection. For the volume Mindrop deals with
/// (a personal list of lookups) this is faster and far less fragile across two
/// processes than a database, and it keeps the share extension trivial.
public struct FileMemoryStore: MemoryStore {
    private let file: CoordinatedFile

    public init(url: URL) {
        self.file = CoordinatedFile(url: url)
    }

    /// The shared store used by both the app and the share extension.
    /// Throws if the App Group entitlement is missing, which is a configuration bug.
    public static func shared() throws -> FileMemoryStore {
        guard let container = AppGroup.containerURL else { throw MemoryStoreError.appGroupUnavailable }
        return FileMemoryStore(url: container.appending(path: AppGroup.memoriesFileName))
    }

    public func load() throws -> [Memory] {
        guard let data = try file.read(), !data.isEmpty else { return [] }
        return try JSONDecoder.mindrop.decode([Memory].self, from: data)
    }

    public func save(_ memories: [Memory]) throws {
        try file.write(try JSONEncoder.mindrop.encode(memories))
    }
}

public enum MemoryStoreError: Error, Equatable, Sendable {
    case appGroupUnavailable
}

/// In-memory store for tests and SwiftUI previews.
public final class InMemoryMemoryStore: MemoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var memories: [Memory]
    /// When set, the next `save` throws, to exercise persistence failure paths.
    public var saveError: Error?

    public init(_ memories: [Memory] = []) {
        self.memories = memories
    }

    public func load() throws -> [Memory] {
        lock.withLock { memories }
    }

    public func save(_ memories: [Memory]) throws {
        if let saveError { throw saveError }
        lock.withLock { self.memories = memories }
    }
}

extension JSONEncoder {
    static var mindrop: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var mindrop: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
