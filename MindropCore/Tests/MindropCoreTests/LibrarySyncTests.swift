import CloudKit
import Foundation
import Testing
@testable import MindropCore

@Suite("iCloud library organization")
@MainActor
struct LibrarySyncTests {
    @Test("Legacy folders and Stack migrate to a device with no local organization")
    func migratesLegacyOrganization() throws {
        struct LegacyFolders: Encodable {
            let folders: [MemoryFolder]
            let assignments: [UUID: UUID]
        }
        let directory = URL.temporaryDirectory.appending(path: "mindrop-library-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appending(path: "folders.json")
        let stackURL = directory.appending(path: "stack.json")
        let travel = MemoryFolder(id: UUID(), name: "Travel")
        let empty = MemoryFolder(id: UUID(), name: "Empty")
        let gate = makeMemory(keyword: "departure gate", value: "C24", at: 20)
        let seat = makeMemory(keyword: "flight seat", value: "18A", at: 30)
        try CoordinatedFile(url: folderURL).write(JSONEncoder.mindrop.encode(
            LegacyFolders(folders: [travel, empty], assignments: [gate.id: travel.id])
        ))
        try CoordinatedFile(url: stackURL).write(JSONEncoder.mindrop.encode([seat.id, gate.id]))
        let folders = MemoryFolders(url: folderURL)
        let stack = MemoryStack(url: stackURL)
        try folders.load()
        try stack.load()
        let (source, _, _) = try makeRepository(memories: [gate, seat], folders: folders, stack: stack)
        let (target, _, _) = try makeRepository()
        #expect(target.libraryRevisions.isEmpty)

        let library = records(in: source)
        try target.applyRemoteLibrary(library.filter { $0.key.kind != .folder })
        _ = try target.applyRemote([gate, seat], deletedIDs: [])
        #expect(target.stackMemories.map(\.id) == [seat.id, gate.id])
        #expect(target.folders.folderID(for: gate.id) == MemoryFolders.generalID)

        try target.applyRemoteLibrary(library.filter { $0.key.kind == .folder })
        #expect(target.folders.custom.map(\.id) == [travel.id, empty.id])
        #expect(target.folders.folderID(for: gate.id) == travel.id)
        #expect(target.folders.folderID(for: seat.id) == MemoryFolders.generalID)
    }

    @Test("An offline reorder keeps the position change without undoing a removal")
    func mergesReorderWithRemoval() throws {
        let gate = makeMemory(keyword: "departure gate", value: "C24", at: 20)
        let seat = makeMemory(keyword: "flight seat", value: "18A", at: 30)
        let (phone, _, _) = try makeRepository(memories: [gate, seat])
        let (mac, _, _) = try makeRepository(memories: [gate, seat])
        try phone.setStackMembership([gate.id, seat.id], included: true)
        try mac.applyRemoteLibrary(records(in: phone))

        try phone.setStackMembership([seat.id], included: false)
        try mac.reorderStack([seat.id, gate.id])
        let phoneChanges = records(in: phone)
        try phone.applyRemoteLibrary(records(in: mac))
        try mac.applyRemoteLibrary(phoneChanges)

        #expect(phone.stackMemories.map(\.id) == [gate.id])
        #expect(mac.stackMemories.map(\.id) == [gate.id])
        #expect(records(in: phone) == records(in: mac))
    }

    @Test("Explicit removal and General override imported membership")
    func clearWinsOverLegacy() throws {
        let folder = UUID()
        let memory = UUID()
        let placementID = CloudLibraryRecord.ID(kind: .placement, uuid: memory)
        let stackID = CloudLibraryRecord.ID(kind: .stack, uuid: memory)
        let oldPosition = LibraryStackPosition(membership: .legacy(true), rank: .legacy(0))
        let (repository, _, _) = try makeRepository()
        let cleared = LibraryStackPosition(membership: .set(nil, replacing: oldPosition.membership), rank: oldPosition.rank)
        let expected: [CloudLibraryRecord.ID: LibraryRecord] = [
            placementID: .placement(.set(nil, replacing: .legacy(folder))),
            stackID: .stack(cleared),
        ]
        try repository.applyRemoteLibrary(expected)
        try repository.applyRemoteLibrary([placementID: .placement(.legacy(folder)), stackID: .stack(oldPosition)])
        #expect(records(in: repository) == expected)
    }

    @Test("Folder names use an encrypted CloudKit field and never decode as a memory")
    func encryptedMetadataRoundTrip() throws {
        let id = CloudLibraryRecord.ID(kind: .folder, uuid: UUID())
        let value = LibraryRecord.folder(.legacy(LibraryFolderDetails(name: "Travel", order: 1)))
        let record = CKRecord(recordType: CloudLibraryRecord.recordType, recordID: id.cloudID)
        try CloudLibraryRecord.fill(record, from: value)

        #expect(record["payload"] == nil)
        #expect(CloudRecord.memoryID(of: record.recordID) == nil)
        #expect(CloudRecord.memory(from: record) == nil)
        let decoded = try #require(CloudLibraryRecord.read(record))
        #expect(decoded.0 == id)
        #expect(decoded.1 == value)
    }

    private func records(in repository: MemoryRepository) -> [CloudLibraryRecord.ID: LibraryRecord] {
        Dictionary(uniqueKeysWithValues: repository.libraryRevisions.keys.compactMap { id in
            repository.libraryRecord(for: id).map { (id, $0) }
        })
    }
}
