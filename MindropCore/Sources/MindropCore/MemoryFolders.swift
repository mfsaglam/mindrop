import Foundation
import Observation

public struct MemoryFolder: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
}

/// The local folder index. Folder changes and assignments have their own revisions,
/// independent of edits to a memory's content.
@available(watchOS 10.0, *)
@MainActor
@Observable
public final class MemoryFolders {
    public static let generalID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    public enum ValidationError: Error {
        case emptyName
        case unknownFolder
    }

    private struct LegacyIndex: Decodable {
        var folders: [MemoryFolder] = []
        var assignments: [UUID: UUID] = [:]
    }

    private struct Index: Codable, Equatable {
        var definitions: [UUID: LibraryChange<LibraryFolderDetails>] = [:]
        var placements: [UUID: LibraryChange<UUID>] = [:]
    }

    private var index = Index()
    private let file: CoordinatedFile?
    var onLocalChange: (() -> Void)?

    public init(url: URL? = nil) {
        file = url.map { CoordinatedFile(url: $0) }
    }

    public var custom: [MemoryFolder] {
        index.definitions.compactMap { id, change in
            change.value.map { (id: id, details: $0) }
        }
        .sorted { ($0.details.order, $0.id.uuidString) < ($1.details.order, $1.id.uuidString) }
        .map { MemoryFolder(id: $0.id, name: $0.details.name) }
    }

    var definitions: [UUID: LibraryChange<LibraryFolderDetails>] { index.definitions }
    var placements: [UUID: LibraryChange<UUID>] { index.placements }

    public func load() throws {
        guard let file else { return }
        index = try Self.decode(file.read())
    }

    public func folderID(for memoryID: UUID) -> UUID {
        guard let folderID = index.placements[memoryID]?.value,
              index.definitions[folderID]?.value != nil else {
            return Self.generalID
        }
        return folderID
    }

    public func add(named rawName: String) throws {
        let name = try Self.validatedName(rawName)
        try update { index in
            let order = index.definitions.values.compactMap { $0.value?.order }.max() ?? -1
            index.definitions[UUID()] = .set(LibraryFolderDetails(name: name, order: order + 1), replacing: nil)
        }
    }

    public func rename(_ id: UUID, to rawName: String) throws {
        let name = try Self.validatedName(rawName)
        try update { index in
            guard let previous = index.definitions[id], let details = previous.value else {
                throw ValidationError.unknownFolder
            }
            guard details.name != name else { return }
            index.definitions[id] = .set(LibraryFolderDetails(name: name, order: details.order), replacing: previous)
        }
    }

    func assign(_ memoryID: UUID, to folderID: UUID) throws {
        try assign([memoryID], to: folderID)
    }

    func assign(_ memoryIDs: [UUID], to folderID: UUID) throws {
        try update { index in
            let isGeneral = folderID == Self.generalID
            guard isGeneral || index.definitions[folderID]?.value != nil else {
                throw ValidationError.unknownFolder
            }
            for memoryID in memoryIDs {
                let previous = index.placements[memoryID]
                let destination: UUID? = isGeneral ? nil : folderID
                if let previous, previous.value == destination { continue }
                index.placements[memoryID] = .set(destination, replacing: previous)
            }
        }
    }

    func remove(_ id: UUID, deletingMemories: ([UUID]) throws -> Void) throws {
        try update { index in
            guard let previous = index.definitions[id], previous.value != nil else {
                throw ValidationError.unknownFolder
            }
            let members = index.placements.compactMap { $0.value.value == id ? $0.key : nil }
            // Keep the folder until its memories are safely in Recently Deleted.
            // A retry leaves any existing deletion timestamps alone.
            try deletingMemories(members)
            // Keeping the assignment lets a concurrent move to another folder win on its own.
            // A deleted folder's UUID resolves to General, including on recovery from the trash.
            index.definitions[id] = .set(nil, replacing: previous)
        }
    }

    func applyRemote(
        definitions: [UUID: LibraryChange<LibraryFolderDetails>], placements: [UUID: LibraryChange<UUID>]
    ) throws {
        guard !definitions.isEmpty || !placements.isEmpty else { return }
        try update(isLocal: false) { index in
            index.definitions.merge(definitions) { $0.merging($1) }
            index.placements.merge(placements) { $0.merging($1) }
        }
    }

    #if os(iOS) || os(macOS)
    func restore(
        _ folders: [DriveBackupLibrary.Folder], memoryIDs: [UUID: UUID], restoredFolderID: ((UUID) -> UUID)? = nil
    ) throws {
        guard !folders.isEmpty else { return }
        try update(isLocal: false) { index in
            var order = (index.definitions.values.compactMap { $0.value?.order }.max() ?? -1) + 1
            for folder in folders where folder.id != Self.generalID {
                var id = folder.id
                if let previous = index.definitions[id], previous.value == nil {
                    guard let restoredFolderID else { continue }
                    id = restoredFolderID(id)
                }
                if index.definitions[id] == nil {
                    // A restored definition must yield to newer folder edits from iCloud Sync.
                    index.definitions[id] = .legacy(LibraryFolderDetails(name: folder.name, order: order))
                    order += 1
                }
                guard index.definitions[id]?.value != nil else { continue }
                for source in folder.memoryIDs {
                    guard let memoryID = memoryIDs[source], index.placements[memoryID] == nil else { continue }
                    index.placements[memoryID] = .legacy(id)
                }
            }
        }
    }
    #endif

    private func update(isLocal: Bool = true, _ change: (inout Index) throws -> Void) throws {
        var updated = index
        var changed = false
        if let file {
            try file.update { data in
                let previous = try Self.decode(data)
                updated = previous
                try change(&updated)
                changed = updated != previous
                return changed ? try JSONEncoder.mindrop.encode(updated) : nil
            }
        } else {
            try change(&updated)
            changed = updated != index
        }
        if updated != index { index = updated }
        if changed, isLocal { onLocalChange?() }
    }

    private static func decode(_ data: Data?) throws -> Index {
        guard let data else { return Index() }
        let decoder = JSONDecoder.mindrop
        if let index = try? decoder.decode(Index.self, from: data) { return index }
        let legacy = try decoder.decode(LegacyIndex.self, from: data)
        var index = Index()
        for (order, folder) in legacy.folders.enumerated() {
            index.definitions[folder.id] = .legacy(LibraryFolderDetails(name: folder.name, order: order))
        }
        index.placements = legacy.assignments.mapValues { .legacy($0) }
        return index
    }

    private static func validatedName(_ rawName: String) throws -> String {
        let name = MemoryNormalizer.normalizeValue(rawName)
        guard !name.isEmpty else { throw ValidationError.emptyName }
        return name
    }
}
