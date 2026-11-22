import Foundation
import Observation

public struct MemoryFolder: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
}

/// A local folder index alongside the memory store. Membership follows the memory ID,
/// so edits, share-extension saves, and CloudKit updates can keep their existing format.
@available(watchOS 10.0, *)
@MainActor
@Observable
public final class MemoryFolders {
    public static let generalID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    public enum ValidationError: Error {
        case emptyName
        case unknownFolder
    }

    private struct Index: Codable {
        var folders: [MemoryFolder] = []
        var assignments: [UUID: UUID] = [:]
    }

    private var index = Index()
    private let file: CoordinatedFile?

    public init(url: URL? = nil) {
        file = url.map { CoordinatedFile(url: $0) }
    }

    public var custom: [MemoryFolder] { index.folders }

    public func load() throws {
        guard let file else { return }
        index = try Self.decode(file.read())
    }

    public func folderID(for memoryID: UUID) -> UUID {
        guard let folderID = index.assignments[memoryID],
              custom.contains(where: { $0.id == folderID }) else {
            return Self.generalID
        }
        return folderID
    }

    public func add(named rawName: String) throws {
        let name = MemoryNormalizer.normalizeValue(rawName)
        guard !name.isEmpty else { throw ValidationError.emptyName }
        let folder = MemoryFolder(id: UUID(), name: name)
        try update { $0.folders.append(folder) }
    }

    func assign(_ memoryID: UUID, to folderID: UUID) throws {
        try update { index in
            if folderID == Self.generalID {
                index.assignments.removeValue(forKey: memoryID)
            } else {
                guard index.folders.contains(where: { $0.id == folderID }) else {
                    throw ValidationError.unknownFolder
                }
                index.assignments[memoryID] = folderID
            }
        }
    }

    func remove(_ id: UUID, deletingMemories: ([UUID]) throws -> Void) throws {
        try update { index in
            guard let position = index.folders.firstIndex(where: { $0.id == id }) else {
                throw ValidationError.unknownFolder
            }
            let members = index.assignments.compactMap { $0.value == id ? $0.key : nil }
            // Keep the folder until its memories are safely in Recently Deleted.
            // A retry leaves any existing deletion timestamps alone.
            try deletingMemories(members)
            index.folders.remove(at: position)
            index.assignments = index.assignments.filter { $0.value != id }
        }
    }

    private func update(_ change: (inout Index) throws -> Void) throws {
        guard let file else {
            try change(&index)
            return
        }
        var updated = index
        try file.update { data in
            updated = try Self.decode(data)
            try change(&updated)
            return try JSONEncoder.mindrop.encode(updated)
        }
        index = updated
    }

    private static func decode(_ data: Data?) throws -> Index {
        guard let data else { return Index() }
        return try JSONDecoder.mindrop.decode(Index.self, from: data)
    }
}
