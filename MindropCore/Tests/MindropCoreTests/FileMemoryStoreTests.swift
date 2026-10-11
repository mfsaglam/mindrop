import Foundation
import Testing
@testable import MindropCore

@Suite("File-backed storage")
struct FileMemoryStoreTests {
    private func temporaryURL() -> URL {
        URL.temporaryDirectory
            .appending(path: "mindrop-tests-\(UUID().uuidString)")
            .appending(path: "memories.json")
    }

    @Test("An empty store reads as no memories rather than failing")
    func emptyStore() throws {
        #expect(try FileMemoryStore(url: temporaryURL()).load().isEmpty)
    }

    @Test("Memories survive a round trip through the file")
    func roundTrip() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = FileMemoryStore(url: url)
        let memories = [
            makeMemory(keyword: "wifi", value: "SuperFast2026!", at: 1),
            makeMemory(keyword: "iban", value: "TR12 3456 7890", at: 2),
        ]
        try store.save(memories)

        // A second instance stands in for the share extension reading the same file.
        #expect(try FileMemoryStore(url: url).load() == memories)
    }

    @Test("Saving again replaces the previous contents")
    func overwrites() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = FileMemoryStore(url: url)
        try store.save([makeMemory(keyword: "a", at: 1), makeMemory(keyword: "b", at: 2)])
        try store.save([makeMemory(keyword: "c", at: 3)])

        #expect(try store.load().map(\.keyword) == ["c"])
    }
}
