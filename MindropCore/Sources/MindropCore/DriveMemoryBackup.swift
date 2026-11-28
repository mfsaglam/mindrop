#if os(iOS) || os(macOS)
import CryptoKit
import Foundation
import Security

public struct DriveBackupLibrary: Codable, Sendable {
    struct Folder: Codable, Sendable {
        let id: UUID
        let name: String
        let memoryIDs: [UUID]
    }

    let memories: [Memory]
    let folders: [Folder]

    public var isEmpty: Bool { memories.isEmpty && folders.isEmpty }
}

public struct DriveBackupSnapshot: Sendable {
    let id: UUID
    let createdAt: Date
    let library: DriveBackupLibrary
}

public actor DriveMemoryBackup {
    public enum LatestBackup: Sendable {
        case notFound
        case downloading
        case ready(DriveBackupSnapshot)
    }

    public struct Status: Sendable {
        public let lastUploadedAt: Date?
        public let uploadPending: Bool
        public let uploadError: String?
    }

    private struct Receipt: Codable {
        let name: String
        let createdAt: Date
        let fingerprint: Data
    }

    private struct History: Codable {
        var latest: Receipt?
        var lastAutomaticAt: Date?
        var lastUploadedAt: Date?
    }

    private let files = FileManager.default
    private let defaults = UserDefaults.standard
    private let historyKey = "driveBackupHistory"
    private let identityKey = "driveBackupIdentity"
    private let localKeyID = "driveBackupEncryptionKeyID"

    public init() {}

    /// An explicit opt-in or manual save can move backups to a different Drive account.
    public func authorizeCurrentAccount(allowAccountChange: Bool = true) throws {
        let token = try currentIdentity()
        if !matchesStoredIdentity(token) {
            guard allowAccountChange || defaults.data(forKey: identityKey) == nil else {
                throw DriveBackupError.accountChanged
            }
            defaults.removeObject(forKey: historyKey)
            defaults.removeObject(forKey: localKeyID)
            let encoded = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
            defaults.set(encoded, forKey: identityKey)
        }
    }

    public func prepareDiscovery(automaticBackupsEnabled: Bool) throws -> Bool {
        if !automaticBackupsEnabled, defaults.data(forKey: identityKey) == nil { return false }
        try authorizeCurrentAccount(allowAccountChange: false)
        _ = try backupDirectory()
        return true
    }

    @discardableResult
    public func create(library: DriveBackupLibrary, automatically: Bool, discovered: [URL] = []) throws -> Bool {
        let now = Date()
        let token = try currentIdentity()
        guard matchesStoredIdentity(token) else { throw DriveBackupError.accountChanged }
        var history = loadHistory()
        if automatically, !DriveBackupPolicy.isDue(lastAutomaticAt: history.lastAutomaticAt, now: now) {
            return false
        }
        let payload = try DriveBackupCodec.encodeLibrary(library)
        if automatically, history.latest == nil,
           let newest = try managedFiles(discovered: discovered).first,
           let snapshot = try? openWhenDownloaded(newest),
           try DriveBackupCodec.encodeLibrary(snapshot.library) == payload {
            // A restored or newly synced device may already have an identical Drive backup.
            return false
        }
        let (keyID, key) = try encryptionKey()
        let fingerprint = Data(HMAC<SHA256>.authenticationCode(for: payload, using: key))
        let directory = try backupDirectory()
        if automatically, let latest = history.latest, latest.fingerprint == fingerprint,
           Self.hasUsableFile(at: directory.appending(path: latest.name)) {
            return false
        }

        let id = UUID()
        let name = "Mindrop-\(Self.fileDate(now))-\(id.uuidString).mindropbackup"
        let data = try DriveBackupCodec.seal(library, id: id, createdAt: now, keyID: keyID, key: key)
        guard token.isEqual(try currentIdentity()) else { throw DriveBackupError.accountChanged }
        try CoordinatedFile(url: directory.appending(path: name)).write(data)
        history.latest = Receipt(name: name, createdAt: now, fingerprint: fingerprint)
        if automatically { history.lastAutomaticAt = now }
        saveHistory(history)
        return true
    }

    public func status() throws -> Status {
        let token = try currentIdentity()
        guard matchesStoredIdentity(token) else { throw DriveBackupError.accountChanged }
        var history = loadHistory()
        guard let latest = history.latest else {
            return Status(lastUploadedAt: history.lastUploadedAt, uploadPending: false, uploadError: nil)
        }
        let url = try backupDirectory().appending(path: latest.name)
        guard files.fileExists(atPath: url.path) else {
            return Status(lastUploadedAt: history.lastUploadedAt, uploadPending: false, uploadError: nil)
        }
        let values = try url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey])
        if values.ubiquitousItemIsUploaded == true {
            history.lastUploadedAt = latest.createdAt
            saveHistory(history)
            return Status(lastUploadedAt: latest.createdAt, uploadPending: false, uploadError: nil)
        }
        let error = values.ubiquitousItemUploadingError?.localizedDescription
        return Status(lastUploadedAt: history.lastUploadedAt, uploadPending: error == nil, uploadError: error)
    }

    public func open(_ url: URL) throws -> DriveBackupSnapshot {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try CoordinatedFile(url: url).read() else { throw DriveBackupError.invalidFile }
        return try DriveBackupCodec.open(data, key: BackupKeychain.load)
    }

    public func latestBackup(discovered: [URL]) throws -> LatestBackup {
        let token = try currentIdentity()
        guard matchesStoredIdentity(token) else { throw DriveBackupError.accountChanged }
        guard let newest = try managedFiles(discovered: discovered).first else { return .notFound }
        let snapshot = try openWhenDownloaded(newest)
        guard token.isEqual(try currentIdentity()) else { throw DriveBackupError.accountChanged }
        return snapshot.map(LatestBackup.ready) ?? .downloading
    }

    /// Keeps three uploaded snapshots and leaves pending uploads alone. Verify the newest
    /// snapshot can actually be decrypted before removing any older ones.
    public func prune(discovered: [URL]) throws {
        let token = try currentIdentity()
        guard matchesStoredIdentity(token) else { throw DriveBackupError.accountChanged }
        let uploaded = try managedFiles(discovered: discovered).filter { url in
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemHasUnresolvedConflictsKey
            ])
            return values?.ubiquitousItemIsUploaded == true && values?.ubiquitousItemHasUnresolvedConflicts != true
                && values?.isDirectory != true && values?.isSymbolicLink != true
        }
        let obsolete = uploaded.dropFirst(DriveBackupPolicy.retainedCount)
        guard !obsolete.isEmpty, let newest = uploaded.first, try openWhenDownloaded(newest) != nil else { return }
        for url in obsolete {
            guard token.isEqual(try currentIdentity()) else { throw DriveBackupError.accountChanged }
            do {
                try CoordinatedFile(url: url).remove()
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                // Another device already removed this file.
            }
        }
    }

    private func managedFiles(discovered: [URL]) throws -> [URL] {
        let directory = try backupDirectory()
        let local: [URL]
        do {
            local = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            local = []
        }
        return DriveBackupPolicy.managedFiles(discovered + local, in: directory)
    }

    private func openWhenDownloaded(_ url: URL) throws -> DriveBackupSnapshot? {
        let values = try url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadRequestedKey, .ubiquitousItemDownloadingErrorKey
        ])
        if let status = values.ubiquitousItemDownloadingStatus, status != .current {
            if values.ubiquitousItemDownloadRequested != true || values.ubiquitousItemDownloadingError != nil {
                try files.startDownloadingUbiquitousItem(at: url)
            }
            return nil
        }
        return try open(url)
    }

    private func backupDirectory() throws -> URL {
        guard let container = files.url(forUbiquityContainerIdentifier: CloudRecord.containerIdentifier) else {
            throw DriveBackupError.driveUnavailable
        }
        return container.appending(path: "Documents/Backups", directoryHint: .isDirectory)
    }

    private func currentIdentity() throws -> NSObject {
        guard let token = files.ubiquityIdentityToken as? NSObject else { throw DriveBackupError.driveUnavailable }
        return token
    }

    private func matchesStoredIdentity(_ token: NSObject) -> Bool {
        guard let encoded = defaults.data(forKey: identityKey),
              let saved = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encoded)
        else { return false }
        return token.isEqual(saved)
    }

    private func encryptionKey() throws -> (UUID, SymmetricKey) {
        if let record = defaults.string(forKey: localKeyID), let id = UUID(uuidString: record) {
            do { return (id, try BackupKeychain.load(id)) }
            catch DriveBackupError.keyUnavailable { }
        }
        let id = UUID()
        let key = SymmetricKey(size: .bits256)
        try BackupKeychain.save(key, id: id)
        defaults.set(id.uuidString, forKey: localKeyID)
        return (id, key)
    }

    private func loadHistory() -> History {
        guard let data = defaults.data(forKey: historyKey),
              let history = try? JSONDecoder().decode(History.self, from: data) else { return History() }
        return history
    }

    private func saveHistory(_ history: History) {
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: historyKey) }
    }

    private static func hasUsableFile(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemUploadingErrorKey]),
              values.isUbiquitousItem == true || FileManager.default.fileExists(atPath: url.path)
        else { return false }
        return values.ubiquitousItemUploadingError == nil
    }

    private static func fileDate(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "yyyy-MM-dd-HHmmss'Z'"
        return format.string(from: date)
    }
}

enum DriveBackupPolicy {
    static let retainedCount = 3

    static func isDue(lastAutomaticAt: Date?, now: Date) -> Bool {
        guard let lastAutomaticAt else { return true }
        return now.timeIntervalSince(lastAutomaticAt) >= 24 * 60 * 60
    }

    static func managedFiles(_ urls: [URL], in directory: URL) -> [URL] {
        let directoryPath = directory.standardizedFileURL.path
        var seen = Set<String>()
        return urls.filter { url in
            url.isFileURL && url.deletingLastPathComponent().standardizedFileURL.path == directoryPath
                && url.lastPathComponent.wholeMatch(of: /^Mindrop-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}Z-[A-Fa-f0-9-]{36}\.mindropbackup$/) != nil
                && UUID(uuidString: String(url.deletingPathExtension().lastPathComponent.suffix(36))) != nil
                && seen.insert(url.lastPathComponent).inserted
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

enum DriveBackupCodec {
    private struct Header: Codable {
        let version: Int
        let keyID: UUID

        var authenticationData: Data { Data("Mindrop backup \(version) \(keyID.uuidString)".utf8) }
    }

    private struct Envelope: Codable {
        let header: Header
        let sealed: Data
    }

    private struct LegacySnapshot: Decodable {
        let id: UUID
        let createdAt: Date
        let memories: Data
    }

    private struct Snapshot: Codable {
        let id: UUID
        let createdAt: Date
        let library: DriveBackupLibrary
    }

    static func encodeLibrary(_ library: DriveBackupLibrary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let folders = library.folders.map { folder in
            DriveBackupLibrary.Folder(id: folder.id, name: folder.name, memoryIDs: folder.memoryIDs.sorted {
                $0.uuidString < $1.uuidString
            })
        }
        return try encoder.encode(DriveBackupLibrary(
            memories: library.memories.sorted { $0.id.uuidString < $1.id.uuidString }, folders: folders
        ))
    }

    static func seal(_ library: DriveBackupLibrary, id: UUID, createdAt: Date, keyID: UUID, key: SymmetricKey) throws -> Data {
        let header = Header(version: 2, keyID: keyID)
        let payload = try JSONEncoder().encode(Snapshot(id: id, createdAt: createdAt, library: library))
        let compressed = try (payload as NSData).compressed(using: .lzfse) as Data
        guard let combined = try AES.GCM.seal(compressed, using: key, authenticating: header.authenticationData).combined else {
            throw DriveBackupError.invalidFile
        }
        return try JSONEncoder().encode(Envelope(header: header, sealed: combined))
    }

    static func open(_ data: Data, key: (UUID) throws -> SymmetricKey) throws -> DriveBackupSnapshot {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard (1...2).contains(envelope.header.version) else { throw DriveBackupError.invalidFile }
        let key = try key(envelope.header.keyID)
        let cleartext = try AES.GCM.open(
            AES.GCM.SealedBox(combined: envelope.sealed), using: key, authenticating: envelope.header.authenticationData
        )
        let snapshot: Snapshot
        if envelope.header.version == 1 {
            let legacy = try decoder.decode(LegacySnapshot.self, from: cleartext)
            let memories = try decoder.decode([Memory].self, from: legacy.memories)
            snapshot = Snapshot(id: legacy.id, createdAt: legacy.createdAt, library: .init(memories: memories, folders: []))
        } else {
            let payload = try (cleartext as NSData).decompressed(using: .lzfse) as Data
            snapshot = try decoder.decode(Snapshot.self, from: payload)
        }
        let library = snapshot.library
        let memoryIDs = Set(library.memories.map(\.id))
        let assignedIDs = library.folders.flatMap(\.memoryIDs)
        guard memoryIDs.count == library.memories.count,
              Set(library.folders.map(\.id)).count == library.folders.count,
              Set(assignedIDs).count == assignedIDs.count,
              memoryIDs.isSuperset(of: assignedIDs)
        else { throw DriveBackupError.invalidFile }
        return DriveBackupSnapshot(id: snapshot.id, createdAt: snapshot.createdAt, library: library)
    }
}

public enum DriveBackupError: Error {
    case driveUnavailable
    case accountChanged
    case keyUnavailable
    case invalidFile
    case keychain(OSStatus)
}

private enum BackupKeychain {
    private static func attributes(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "mfsaglam.Mindrop.DriveBackup",
            kSecAttrAccount as String: id.uuidString,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: true
        ]
    }

    static func load(_ id: UUID) throws -> SymmetricKey {
        var query = attributes(for: id)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        if result == errSecItemNotFound { throw DriveBackupError.keyUnavailable }
        guard result == errSecSuccess else { throw DriveBackupError.keychain(result) }
        guard let data = item as? Data, data.count == 32 else { throw DriveBackupError.invalidFile }
        return SymmetricKey(data: data)
    }

    static func save(_ key: SymmetricKey, id: UUID) throws {
        var query = attributes(for: id)
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let result = SecItemAdd(query as CFDictionary, nil)
        guard result == errSecSuccess else { throw DriveBackupError.keychain(result) }
    }
}
#endif
