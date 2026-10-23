import Foundation
import Combine
import MindropCore
import WatchConnectivity
import os

/// Gets memories saved on the watch to the iPhone, which files them, adds them to Spotlight
/// and categorises them. The watch keeps nothing else: no library, so nothing sensitive
/// lives on the wrist.
///
/// Each memory goes two ways, and arriving twice is harmless, since it has one identifier:
/// - to the iPhone as a WatchConnectivity user-info transfer, which the system queues and
///   delivers whenever the iPhone is reachable, even if Mindrop is closed on either side;
/// - straight to iCloud, only while the iPhone says iCloud Sync is on, so a memory reaches
///   the iPhone through iCloud even when the iPhone is far away.
///
/// A memory waits here, in a small file, until the iPhone has it or iCloud has it.
///
/// An `ObservableObject` rather than `@Observable`, which needs watchOS 10: the app runs as
/// far back as watchOS 9, the oldest Xcode 27 builds for (Series 4, Series 5, first SE).
@MainActor
final class WatchSender: NSObject, ObservableObject {
    private struct Entry: Codable {
        var memory: Memory
        /// Given to WatchConnectivity, whose queue survives relaunches.
        var handedToPhone = false
        /// iCloud has it.
        var inICloud = false
        /// iCloud is not an option for it (no account, or the iPhone never synced): it
        /// reaches the iPhone through WatchConnectivity only.
        var skipsICloud = false
    }

    @Published private var entries: [Entry] = []
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private let fileURL = URL.applicationSupportDirectory.appending(path: "outbox.json")
    private var isUploading = false
    private let log = Logger(subsystem: "mfsaglam.Mindrop.watchkitapp", category: "sender")

    /// Saved here, but neither the iPhone nor iCloud has it yet.
    var waitingCount: Int { entries.count }

    override init() {
        super.init()
        entries = load()
        session?.delegate = self
        session?.activate()
        #if DEBUG
        // `-debugSave "keyword=value"` saves a memory at launch, for testing the way to the
        // iPhone without typing on the watch.
        if let pair = UserDefaults.standard.string(forKey: "debugSave"), let separator = pair.firstIndex(of: "=") {
            _ = save(keyword: String(pair[..<separator]), value: String(pair[pair.index(after: separator)...]), isSensitive: false)
        }
        #endif
    }

    /// Saves what was typed and starts sending it. False if the keyword or the value is
    /// empty.
    func save(keyword: String, value: String, isSensitive: Bool) -> Bool {
        guard let memory = WatchHandoff.newMemory(keyword: keyword, value: value, isSensitive: isSensitive) else {
            return false
        }
        entries.append(Entry(memory: memory))
        persist()
        send()
        return true
    }

    /// Hands every waiting memory to the iPhone and, when allowed, to iCloud, then forgets
    /// the ones that arrived. Cheap: called on launch, on returning to the screen and
    /// whenever WatchConnectivity reports progress.
    func send() {
        if let session, session.activationState == .activated {
            for index in entries.indices where !entries[index].handedToPhone {
                guard let userInfo = try? WatchHandoff.userInfo(for: entries[index].memory) else { continue }
                session.transferUserInfo(userInfo)
                entries[index].handedToPhone = true
            }
        }
        forgetDelivered()
        Task { await uploadToICloud() }
    }

    /// iCloud only while the iPhone says iCloud Sync is on, and only for memories it lacks.
    private func uploadToICloud() async {
        guard !isUploading, let session else { return }
        guard WatchHandoff.syncsWithICloud(in: session.receivedApplicationContext) else { return }
        isUploading = true
        defer { isUploading = false }
        for memory in entries.filter({ !$0.inICloud && !$0.skipsICloud }).map(\.memory) {
            switch await CloudRecordUpload.save(memory) {
            case .saved:
                update(memory.id) { $0.inICloud = true }
            case .unavailable:
                update(memory.id) { $0.skipsICloud = true }
            case .retryLater:
                // Tried again on the next launch or return to the screen.
                return
            }
        }
        forgetDelivered()
    }

    /// A memory is done once iCloud has it, or once WatchConnectivity has delivered it: it
    /// no longer has a transfer outstanding.
    private func forgetDelivered() {
        let outstanding = Set(
            (session?.outstandingUserInfoTransfers ?? []).compactMap { WatchHandoff.memory(from: $0.userInfo)?.id }
        )
        let before = entries.count
        entries.removeAll { entry in
            entry.inICloud || (entry.handedToPhone && !outstanding.contains(entry.memory.id))
        }
        if entries.count != before { persist() }
    }

    private func update(_ id: UUID, _ change: (inout Entry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.memory.id == id }) else { return }
        change(&entries[index])
        persist()
    }

    /// A transfer that failed, for instance because Mindrop is not installed on the iPhone,
    /// is tried again later.
    private func transferFailed(for id: UUID) {
        update(id) { $0.handedToPhone = false }
    }

    private func load() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            log.error("Could not save the outbox: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WatchSender: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.send() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.send() }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let id = WatchHandoff.memory(from: userInfoTransfer.userInfo)?.id
        let failed = error != nil
        Task { @MainActor in
            if failed, let id { self.transferFailed(for: id) }
            self.send()
        }
    }
}
