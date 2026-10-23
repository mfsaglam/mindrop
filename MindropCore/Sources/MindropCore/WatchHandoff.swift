import Foundation

/// What the Apple Watch and the iPhone say to each other through WatchConnectivity, kept
/// here so both sides read and write it the same way. Plain property-list values only,
/// which is all WatchConnectivity carries.
///
/// The watch only adds memories. Each one goes to the iPhone as a user-info transfer, which
/// the system queues and delivers even if either app is closed, and the iPhone takes it in
/// like a memory synced from another device. The iPhone tells the watch, through the
/// application context, whether iCloud Sync is on, so the watch saves to iCloud only when
/// the user lets Mindrop use it.
public enum WatchHandoff {
    private static let memoryKey = "memory"
    private static let syncsWithICloudKey = "syncsWithICloud"

    /// A memory saved on the watch, as a user-info transfer.
    public static func userInfo(for memory: Memory) throws -> [String: Any] {
        [memoryKey: try JSONEncoder().encode(memory)]
    }

    /// The memory in a user-info transfer, or nil if it holds none this version can read.
    public static func memory(from userInfo: [String: Any]) -> Memory? {
        guard let data = userInfo[memoryKey] as? Data else { return nil }
        return try? JSONDecoder().decode(Memory.self, from: data)
    }

    /// The iPhone's iCloud Sync setting, as an application context.
    public static func applicationContext(syncsWithICloud: Bool) -> [String: Any] {
        [syncsWithICloudKey: syncsWithICloud]
    }

    /// Whether the iPhone said iCloud Sync is on. False until it has said so: the watch
    /// does not write to iCloud on a guess.
    public static func syncsWithICloud(in context: [String: Any]) -> Bool {
        context[syncsWithICloudKey] as? Bool ?? false
    }

    /// A new memory from what was typed on the watch, normalised as the app does, or nil if
    /// the keyword or the value is empty.
    public static func newMemory(keyword: String, value: String, isSensitive: Bool, now: Date = .now) -> Memory? {
        let keyword = MemoryNormalizer.normalizeKeyword(keyword)
        let value = MemoryNormalizer.normalizeValue(value)
        guard !keyword.isEmpty, !value.isEmpty else { return nil }
        return Memory(keyword: keyword, value: value, createdAt: now, updatedAt: now, isSensitive: isSensitive)
    }
}
