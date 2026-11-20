#if os(iOS) || os(macOS)
import CryptoKit
import Foundation
import Security

public actor DriveMemoryBackup {
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

    /// An explicit opt-in or manual save associates this device with the current Drive account.
    public func authorizeCurrentAccount() throws {
        let token = try currentIdentity()
        if !matchesStoredIdentity(token) {
            defaults.removeObject(forKey: historyKey)
            defaults.removeObject(forKey: localKeyID)
            let encoded = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
            defaults.set(encoded, forKey: identityKey)
        }
    }

    @discardableResult
    public func create(memories: [Memory], automatically: Bool) throws -> Bool {
        guard !memories.isEmpty else { return false }
        let now = Date()
        let token = try currentIdentity()
        guard matchesStoredIdentity(token) else { throw DriveBackupError.accountChanged }
        var history = loadHistory()
        if automatically, !DriveBackupPolicy.isDue(lastAutomaticAt: history.lastAutomaticAt, now: now) {
            return false
        }
        let (keyID, key) = try encryptionKey()
        let snapshot = try DriveBackupCodec.encodeMemories(memories)
        let fingerprint = Data(HMAC<SHA256>.authenticationCode(for: snapshot, using: key))
        let directory = try backupDirectory()
        if automatically, let latest = history.latest, latest.fingerprint == fingerprint,
           Self.hasUsableFile(at: directory.appending(path: latest.name)) {
            return false
        }

        let id = UUID()
        let name = "Mindrop-\(Self.fileDate(now))-\(id.uuidString).mindropbackup"
        let data = try DriveBackupCodec.seal(snapshot, id: id, createdAt: now, keyID: keyID, key: key)
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

    public func open(_ url: URL) throws -> (MemoryBackup, [Memory]) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try CoordinatedFile(url: url).read() else { throw DriveBackupError.invalidFile }
        return try DriveBackupCodec.open(data, key: BackupKeychain.load)
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
        guard FileManager.default.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.ubiquitousItemUploadingErrorKey])
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
    static func isDue(lastAutomaticAt: Date?, now: Date) -> Bool {
        guard let lastAutomaticAt else { return true }
        return now.timeIntervalSince(lastAutomaticAt) >= 24 * 60 * 60
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

    private struct Snapshot: Codable {
        let id: UUID
        let createdAt: Date
        let memories: Data
    }

    static func encodeMemories(_ memories: [Memory]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(memories.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    static func seal(_ memories: Data, id: UUID, createdAt: Date, keyID: UUID, key: SymmetricKey) throws -> Data {
        let header = Header(version: 1, keyID: keyID)
        let payload = try JSONEncoder().encode(Snapshot(id: id, createdAt: createdAt, memories: memories))
        guard let combined = try AES.GCM.seal(payload, using: key, authenticating: header.authenticationData).combined else {
            throw DriveBackupError.invalidFile
        }
        return try JSONEncoder().encode(Envelope(header: header, sealed: combined))
    }

    static func open(_ data: Data, key: (UUID) throws -> SymmetricKey) throws -> (MemoryBackup, [Memory]) {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard envelope.header.version == 1 else { throw DriveBackupError.invalidFile }
        let key = try key(envelope.header.keyID)
        let cleartext = try AES.GCM.open(
            AES.GCM.SealedBox(combined: envelope.sealed), using: key, authenticating: envelope.header.authenticationData
        )
        let snapshot = try decoder.decode(Snapshot.self, from: cleartext)
        let memories = try decoder.decode([Memory].self, from: snapshot.memories)
        guard Set(memories.map(\.id)).count == memories.count else { throw DriveBackupError.invalidFile }
        return (MemoryBackup(id: snapshot.id, createdAt: snapshot.createdAt, memoryCount: memories.count), memories)
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
