import CloudKit
import Foundation
import Testing
@testable import MindropCore

@Suite("iCloud sync")
struct CloudSyncTests {
    private func memory(
        value: String = "SuperFast2026!",
        updated: TimeInterval = 0,
        modified: TimeInterval? = nil,
        category: CategoryAssignment? = nil
    ) -> Memory {
        Memory(
            id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
            keyword: "wifi",
            value: value,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: updated),
            category: category,
            modifiedAt: Date(timeIntervalSince1970: modified ?? updated)
        )
    }

    @Test("The later change wins")
    func laterWins() {
        var local = memory(updated: 10)
        local.isSensitive = true
        local.modifiedAt = Date(timeIntervalSince1970: 30)
        let remote = memory(updated: 10, modified: 20)

        #expect(Memory.merged(local: local, remote: remote) == local)
        #expect(Memory.merged(local: remote, remote: local) == local)
    }

    @Test("Newer text survives a later change of something else, with its own category")
    func textSurvives() {
        // This device edited the text at 20; the other filed the old text at 30.
        let local = memory(value: "NewPassword", updated: 20, category: nil)
        let remote = memory(
            value: "SuperFast2026!", updated: 10, modified: 30,
            category: CategoryAssignment(category: .network, source: .automatic, version: 1)
        )

        let merged = Memory.merged(local: local, remote: remote)
        #expect(merged.value == "NewPassword")
        #expect(merged.updatedAt == local.updatedAt)
        #expect(merged.category == nil)
        #expect(merged.modifiedAt == remote.modifiedAt)
    }

    @Test("A category the user picked survives a text edit from elsewhere")
    func manualCategorySurvives() {
        let local = memory(value: "NewPassword", updated: 20)
        let remote = memory(updated: 10, modified: 30, category: CategoryAssignment(category: .home, source: .manual))

        let merged = Memory.merged(local: local, remote: remote)
        #expect(merged.value == "NewPassword")
        #expect(merged.category?.category == .home)
    }

    @Test("A memory survives the trip through a CloudKit record, every field")
    func recordRoundTrip() throws {
        var original = memory(updated: 10, modified: 20, category: CategoryAssignment(category: .network, source: .automatic, version: 3))
        original.expiresAt = Date(timeIntervalSince1970: 40)
        original.deletedAt = Date(timeIntervalSince1970: 50)
        original.isSensitive = true

        let record = CKRecord(recordType: CloudRecord.recordType, recordID: CloudRecord.recordID(for: original.id))
        CloudRecord.fill(record, from: original)
        #expect(record.recordID.zoneID == CloudRecord.zoneID)
        #expect(record["keyword"] == nil)
        #expect(record["value"] == nil)
        #expect(try #require(CloudRecord.memory(from: record)) == original)

        var plain = original
        plain.category = nil
        plain.expiresAt = nil
        plain.deletedAt = nil
        CloudRecord.fill(record, from: plain)
        #expect(CloudRecord.memory(from: record) == plain)
    }

    @Test("A record that is not a whole memory is ignored")
    func incompleteRecord() {
        let record = CKRecord(recordType: CloudRecord.recordType, recordID: CloudRecord.recordID(for: UUID()))
        record.encryptedValues["keyword"] = "wifi"
        #expect(CloudRecord.memory(from: record) == nil)
    }

    @Test("System fields come back as the same record")
    func systemFields() throws {
        let record = CKRecord(recordType: CloudRecord.recordType, recordID: CloudRecord.recordID(for: UUID()))
        let restored = try #require(CloudRecord.record(fromSystemFields: CloudRecord.systemFields(of: record)))
        #expect(restored.recordID == record.recordID)
        #expect(restored.recordType == record.recordType)
    }

    @Test("Pending: anything changed since iCloud last saw it, and anything deleted for good")
    func pendingChanges() {
        let synced = memory(updated: 10)
        let edited = makeMemory(keyword: "door", value: "4821#", at: 20)
        let fresh = makeMemory(keyword: "iban", value: "TR12", at: 30)
        let goneID = UUID()

        var state = CloudSyncState()
        state.known[synced.id] = synced.modifiedAt.addingTimeInterval(0.0004)
        state.known[edited.id] = edited.modifiedAt.addingTimeInterval(-5)
        state.known[goneID] = Date(timeIntervalSince1970: 1)

        let pending = state.pendingChanges(for: [synced, edited, fresh])
        #expect(Set(pending.saves) == [edited.id, fresh.id])
        #expect(pending.deletes == [goneID])
    }

    @Test("The sync state survives a round trip through its file")
    func stateRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cloud-sync-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileCloudSyncStateStore(url: url)
        #expect(try store.load().known.isEmpty)

        var state = CloudSyncState()
        let id = UUID()
        state.known[id] = Date(timeIntervalSince1970: 10)
        state.systemFields[id] = Data([1, 2, 3])
        try store.save(state)

        let loaded = try store.load()
        #expect(loaded.known == state.known)
        #expect(loaded.systemFields == state.systemFields)
    }
}
