import CloudKit
import Foundation
import Observation
import os

struct CloudBackupCatalog: Codable, Equatable, Sendable {
    let accountID: String
    var backups: [UUID: MemoryBackup] = [:]
    var changeToken: Data?

    var orderedBackups: [MemoryBackup] {
        backups.values.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.createdAt > $1.createdAt
        }
    }

    mutating func apply(updates: [MemoryBackup], deletions: [UUID]) {
        for backup in updates { backups[backup.id] = backup }
        for id in deletions { backups[id] = nil }
    }

    static func load(from file: CoordinatedFile, for accountID: String) -> Self? {
        guard let data = try? file.read(),
              let catalog = try? JSONDecoder().decode(Self.self, from: data),
              catalog.accountID == accountID
        else { return nil }
        return catalog
    }

    func save(to file: CoordinatedFile) throws {
        try file.write(try JSONEncoder().encode(self))
    }
}

/// The app's backup summaries and position in the CloudKit backup zone's change history.
/// The cache holds metadata only. Restoring still fetches the snapshot from iCloud.
@available(watchOS 10.0, *)
@MainActor
@Observable
public final class SavedCloudBackups {
    private let cloud = CloudMemoryBackup()
    private let cacheFile: CoordinatedFile?
    private let log = Logger(subsystem: "mfsaglam.Mindrop", category: "icloud-backups")

    private var accountID: String?
    private var accountGeneration = 0
    private var catalogRevision = 0
    private var catalog: CloudBackupCatalog?
    private var refreshTask: Task<Void, Error>?
    @ObservationIgnored private var hasRequestedArchive = false

    public init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        cacheFile = directory.map { CoordinatedFile(url: $0.appending(path: "Mindrop/cloud-backups.json")) }
    }

    public var backups: [MemoryBackup]? { catalog?.orderedBackups }
    public var isRefreshing: Bool { refreshTask != nil }

    public func refresh() async throws {
        hasRequestedArchive = true
        if let refreshTask { return try await refreshTask.value }
        let generation = accountGeneration
        let task = Task {
            defer {
                if generation == self.accountGeneration { self.refreshTask = nil }
            }
            try await self.fetchChanges(generation: generation)
        }
        refreshTask = task
        try await task.value
    }

    public func accountDidChange() {
        accountGeneration += 1
        accountID = nil
        catalog = nil
        refreshTask?.cancel()
        refreshTask = nil
        if hasRequestedArchive { Task { try? await refresh() } }
    }

    public func memories(in backup: MemoryBackup) async throws -> [Memory] {
        let generation = accountGeneration
        let account = try await identifyAccount(generation: generation)
        let memories = try await cloud.memories(in: backup)
        try checkAccount(account, generation: generation)
        return memories
    }

    public func delete(_ backups: [MemoryBackup]) async throws {
        guard !backups.isEmpty, let account = accountID else { return }
        let generation = accountGeneration
        guard try await cloud.accountID() == account else { throw CancellationError() }
        for backup in backups {
            try checkAccount(account, generation: generation)
            guard catalog?.backups[backup.id] == backup else { continue }
            try await cloud.delete(backup)
            try checkAccount(account, generation: generation)
            guard var next = catalog else { return }
            next.apply(updates: [], deletions: [backup.id])
            update(next)
        }
    }

    private func fetchChanges(generation: Int) async throws {
        let account = try await identifyAccount(generation: generation)
        while true {
            let revision = catalogRevision
            let updated = try await cloud.updatedCatalog(from: catalog ?? CloudBackupCatalog(accountID: account))
            try checkAccount(account, generation: generation)
            // A deletion can finish while this request is in flight. Fetch again
            // from the retained cursor rather than overwriting the newer local result.
            guard revision == catalogRevision else { continue }
            update(updated)
            return
        }
    }

    private func identifyAccount(generation: Int) async throws -> String {
        do {
            let account = try await cloud.accountID()
            try Task.checkCancellation()
            guard generation == accountGeneration else { throw CancellationError() }
            if account != accountID {
                accountID = account
                catalog = cacheFile.flatMap { CloudBackupCatalog.load(from: $0, for: account) }
                catalogRevision += 1
            }
            return account
        } catch let error as CKError where error.code == .notAuthenticated {
            if generation == accountGeneration {
                accountID = nil
                catalog = nil
                catalogRevision += 1
            }
            throw error
        }
    }

    private func checkAccount(_ account: String, generation: Int) throws {
        try Task.checkCancellation()
        guard generation == accountGeneration, account == accountID else { throw CancellationError() }
    }

    private func update(_ next: CloudBackupCatalog) {
        guard catalog != next else { return }
        catalog = next
        catalogRevision += 1
        guard let cacheFile else { return }
        do {
            try next.save(to: cacheFile)
        } catch {
            log.error("Could not persist the CloudKit backup catalog")
        }
    }
}
