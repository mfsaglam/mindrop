#if os(macOS)
import Foundation

/// Holds confirmed saves until the main app can add them to its library.
public enum MacShareInbox {
    public static let didSave = Notification.Name("mfsaglam.Mindrop.macShareDidSave")

    public static func save(_ memory: Memory) throws {
        try file().update { data in
            var pending = try decode(data)
            pending.append(memory)
            return try JSONEncoder.mindrop.encode(pending)
        }
        DistributedNotificationCenter.default().postNotificationName(
            didSave, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    static func drain(from file: CoordinatedFile, _ importMemories: ([Memory]) throws -> Void) throws {
        try file.update { data in
            let pending = try decode(data)
            guard !pending.isEmpty else { return nil }
            // Keep the inbox intact if importing failed. The library deduplicates by ID
            // if the process stops after importing but before this write completes.
            try importMemories(pending)
            return try JSONEncoder.mindrop.encode([Memory]())
        }
    }

    private static func decode(_ data: Data?) throws -> [Memory] {
        guard let data else { return [] }
        return try JSONDecoder.mindrop.decode([Memory].self, from: data)
    }

    static func file() throws -> CoordinatedFile {
        let identifier = "RPQ3VF2JBZ.mfsaglam.Mindrop.Share"
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw MemoryStoreError.appGroupUnavailable
        }
        return CoordinatedFile(url: container.appending(path: "pending-memories.json"))
    }
}
#endif
